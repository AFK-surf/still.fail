// The station's protocol driver inside DeepSeek Harness (a Cordis plugin dsh loads from the path its patch names:
// agents/dsh.ts). One line of JSON per message on stdin and stdout, for the one session of the process:
//   in:  {id, op: "open", cwd, resume?, provider?, model?, effort?}   → {id, session} | {id, error, lacks?}
//        (lacks: "tools" where it was refused for the station's tools not being mounted)
//        {id, op: "prompt" | "steer", text}   a message for the next turn, or for the running turn's next step
//        {id, op: "cancel"}                   stops the running turn (it ends aborted)
//   out: {id, ...} answers; {ev: "event", type, data} the session's turns and tool calls as dsh commits them;
//        {ev: "stream", frame} the model's output as it streams (text, thinking, a call's input).
// Plain JavaScript that imports nothing of dsh's: dsh loads it from the station's directory, where its packages do not
// resolve. The station's tools are mounted by the patch (dsh's own mcp-client), not here: its config names that entry
// (`tools`), and no session is opened, so no prompt taken, before it is up (`mounted`).
import { randomUUID } from 'node:crypto'
import { createInterface } from 'node:readline'

export const name = 'stillfail-bridge'
export const inject = ['agents', 'loader']

/// The session events the station reads (the rest stay in dsh's log): a turn's bounds and its tool calls.
const EVENTS = new Set(['turn/start', 'turn/end', 'tool/call', 'tool/result'])
/// The most of a tool's result sent as it is (the whole is in the transcript).
const RESULT_CHARS = 64 * 1024

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

/// Cordis's FiberState.ACTIVE: a plugin whose `apply` returned.
const ACTIVE = 2

/// An error's message with those of its causes (dsh's MCP client says why in the cause).
function reasons(error) {
  const said = []
  for (let e = error; e !== undefined && e !== null && said.length < 4; e = e.cause) said.push(String(e?.message ?? e))
  return said.join(': ')
}

/// Waits until the patch's entry `id` (the station's tools) is up, and throws where it will not be. dsh mounts its
/// plugins side by side and none waits for another: a session opened as soon as this one was up took its first prompt
/// before the MCP client had the station's list of tools, and a step's tools are those registered as it starts, so the
/// model's first request went without them: it could neither post nor end its turn by them until a later step, if the
/// turn had one (dsh 0.2.2-rc.1, 2026-11-14: every time; the list was answered 6 to 20 ms after `open` was, later the
/// longer the station took to give it). The
/// client's `apply` returns once the server's tools are registered, and with failOnStartupError throws where it could
/// not connect or list them, which dsh's startup only warns of (no entry it requires). So the signal is dsh's own:
/// its loader with nothing left to import or start, then that entry's plugin as it ended up. Never a time.
///
/// A patch that names no such entry is a station's from before this (2026-11-14): an update puts this file in place
/// while the station before still runs and starts dsh with its own patch, for as long as the next one takes to come
/// up, or for good where it does not. Its session is opened as it was then, waiting for nothing, rather than refused.
async function mounted(ctx, id) {
  if (id === undefined) return
  await ctx.loader.await()
  let entry
  for (const e of ctx.loader.entries()) if (e.options?.id === id) entry = e
  if (!entry?.fiber) throw lacking(`dsh did not load its plugin ${id} (the station's tools)`)
  try {
    await entry.fiber.await()
  } catch (error) {
    throw lacking(`the station's tools could not be mounted (${reasons(error)})`)
  }
  if (entry.fiber.state !== ACTIVE) throw lacking(`dsh did not start its plugin ${id} (the station's tools)`)
}

/// A refusal for the station's tools not being there, told apart in the answer (`lacks`): the reason under it may
/// read as anything (a connection refused, a timeout), and the station tells its person what this is, not that.
const lacking = (message) => Object.assign(new Error(message), { lacks: 'tools' })

/// The driver on its lines, whoever carries them: `write` is given each message it says, `line` takes each line of the
/// station's, `closed` is for the station's end closing. `apply` gives it the process's stdin and stdout; a test, its
/// own, in a made-up dsh (test/dsh-bridge.test.ts).
export function driver(ctx, config, write) {
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
    async open({ cwd, resume, provider, model, effort }) {
      if (agent !== null) throw new Error('a session is open')
      await mounted(ctx, config?.tools)
      const agentOptions = provider && model ? { provider, model, ...(effort ? { reasoningEffort: effort } : {}) } : undefined
      handle = resume
        ? await ctx.agents.resume({ resumeSessionId: resume, agentOptions })
        : await ctx.agents.create({ sessionId: randomUUID(), meta: { cwd }, agentOptions })
      agent = handle.agent
      // A resumed session goes on with the route its transcript last used (agentOptions only stand in until one is
      // recorded): the one it is opened with now, after its model or effort was changed, is selected (a no-op when the
      // same; a dsh from before model selections takes agentOptions). One that would still run another model is
      // refused rather than run under the station's name for it: the station then starts a new session on it.
      if (resume && agentOptions && agent.model?.select) {
        agent.model.select(agentOptions)
        const running = agent.model.current?.()
        if (running && (running.provider !== provider || running.model !== model)) {
          throw new Error(`resumed on ${running.provider}/${running.model}, not ${provider}/${model}`)
        }
      }
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

  return {
    async line(line) {
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
        write({ id: message.id, error: String(error?.message ?? error), ...(error?.lacks ? { lacks: error.lacks } : {}) })
      }
    },
    closed: () => handle?.dispose() ?? Promise.resolve(),
  }
}

export function apply(ctx, config) {
  const { line, closed } = driver(ctx, config, (message) => process.stdout.write(`${JSON.stringify(message)}\n`))
  const lines = createInterface({ input: process.stdin })
  lines.on('line', line)
  // The station closing stdin ends the process (dsh's own exit disposes the agent and flushes its log).
  lines.on('close', () => {
    void closed().finally(() => process.exit(0))
  })
}
