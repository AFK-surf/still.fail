# Hermes Agent as a runtime

Hermes Agent runs through `hermes acp` (ACP JSON-RPC over stdio), one process per still.fail session. The driver is `station/src/agents/hermes.ts`. Tested against Hermes **0.21.3**, including a real ACP session, a call through the supplied HTTP MCP server, and loading the persisted session after restarting the process. Protocol reference: [Hermes ACP host integration](https://hermes-agent.nousresearch.com/docs/user-guide/features/acp).

## Setup

Install Hermes and its ACP dependency on the station, following Hermes' installation instructions; `hermes acp --check` must pass. The station detects `hermes` on its PATH. Hermes manages its installation and updates; the station does not run an npm or Codex installer for it.

In Accounts → Add account → Custom variables, choose **Hermes Agent**. It is offered only by stations that advertise this runtime. Use an `env` profile. A minimal profile in the station's `config.json` is:

```json
{
  "id": "hermes",
  "runtime": "hermes",
  "home": "homes/hermes",
  "access": { "kind": "env" },
  "models": ["openrouter:anthropic/claude-sonnet-4.6"]
}
```

The model ID is an example; use one your configured provider offers. Configure Hermes in `<absolute profile home>/hermes`, which is the process's `HERMES_HOME`: its `config.yaml`, `.env`, provider login and native `state.db` belong there. For an interactive setup use `HERMES_HOME=<absolute profile home>/hermes hermes model` through the station's login flow. Explicit profile variables can also supply Hermes' provider settings. The machine's usual `~/.hermes` credentials are not copied into the profile. Hermes' own reasoning configuration applies; still.fail does not offer unsupported effort controls or claim to have verified an `env` profile's credentials.

## Sessions and tools

- Initialize ACP, then `session/new` or `session/load`, with the session's working directory and the still.fail HTTP MCP server. Its bearer token is supplied as an HTTP header, never embedded in the prompt.
- If a model is selected, wait for `session/set_model` to succeed before accepting a turn. Leave it unset to use Hermes' default.
- Each `session/prompt` contains the station's instructions as an explicit context block followed by the incoming message. ACP has no portable system-prompt parameter; these are prompt context, not a replacement for Hermes' system prompt. The context names the station's shared memory and skills; shared skills are also linked into the profile's Hermes home. Nothing is written into the user's project.
- Text, thoughts and tool calls stream through `session/update`. The prompt's response ends the turn. `session/cancel` interrupts it. Messages arriving during a turn stay queued in still.fail: Hermes versions differ in how concurrent prompts redirect or queue work.
- Permission requests select `allow_once` only, matching the station's unattended agent execution without creating permanent Hermes allowlist entries. Unsupported client requests return a protocol error rather than hanging.
- Runners preserve running processes across station handover. Snapshots keep partial text and unfinished tools. Crash adoption reconstructs them from acknowledged ACP output. Loading a native session ignores the history replay so it is not recorded twice.

The station keeps its readable transcript at `<profile home>/hermes/sessions/<id>.jsonl`, using the same record format as Cursor and Devin. History and live views read it through the common transcript readers. Hermes' native conversation remains in that profile's `state.db`; resuming it requires the same Hermes home. Cross-profile migration of that native database is not implemented. ACP context estimates are not reported as billable token counts.

## Validation

```sh
node scripts/native.ts run runner mesh archive-rs -- node --test station/test/hermes.test.ts
node scripts/native.ts run runner -- node station/test/hermes-smoke.ts
```

The first runs a strict fake ACP peer under the real runner, covering tools, model selection, instructions, cancellation, failure classification, resumption, handover and crash adoption. The second requires an installed Hermes with ACP and uses a temporary isolated Hermes home, a local deterministic OpenAI-compatible server and a local MCP endpoint. It checks real Hermes tool execution and native resume without calling a paid model or using an existing account.
