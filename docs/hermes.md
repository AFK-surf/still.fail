# Hermes Agent as a runtime

Hermes Agent runs through `hermes acp` (ACP JSON-RPC over stdio), one process per still.fail session. The driver is `station/src/agents/hermes.ts`. Requires Hermes **0.21.7** or newer ([v0.21.7](https://github.com/NousResearch/hermes-agent/tree/v0.21.7)). Older adapters omit completion updates for some tools reached through discovery, losing results in history; the driver rejects these versions before starting a session. Protocol reference: [Hermes ACP host integration](https://hermes-agent.nousresearch.com/docs/user-guide/features/acp).

## Setup

Install Hermes with both its ACP and MCP dependencies on the station, following Hermes' installation instructions; for the v0.21.7 uv checkout, use `uv sync --frozen --extra acp --extra mcp --python 3.14`. `hermes acp --check` checks ACP, but the separate MCP dependency is also required for station tools. The station detects `hermes` on its PATH. Hermes manages its installation and updates; the station does not run an npm or Codex installer for it.

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

## Choosing an existing Hermes configuration

In the Hermes Profile's **Edit variables**, set `HERMES_HOME=/absolute/path/to/.hermes` (or `HERMES_HOME=~/.hermes` for this station's user). New conversations and model discovery then use that home's `config.yaml`, `.env`, `SOUL.md`, memories, skills and native session database. This explicitly shares that Hermes configuration; still.fail does not copy its files or replace its SOUL/memories. An unset or blank value keeps the isolated `<profile home>/hermes` default. Relative paths are rejected.

still.fail keeps its own readable transcripts under the station Profile. Each new conversation records which native Hermes home it uses, so changing this setting does not strand older conversations: resuming one uses its original native home. Transcripts created before home selection was supported use the original isolated home. Start a new conversation to use a newly selected home and its persona/memory.

## Model selection and older clients

The station reads Hermes' `session/new` model inventory when a Hermes profile is checked (including on startup and after it is added). This probe uses that profile's home and explicit environment, supplies no station MCP server, sends no prompt, and closes the process after reading the catalog. Hermes 0.21.7 builds this inventory with `include_unconfigured=False`: only configured providers and configured named endpoints are offered, not every provider Hermes supports. Hermes also considers borrowed Claude/Codex logins configured; the driver points those credential readers into the profile and blocks the shared macOS Claude Keychain entry, so unrelated machine logins do not populate this catalog. An explicitly supplied credential-directory variable can opt into that directory. Only operating-system and transport variables (including proxy and certificate settings) are inherited from the station. Provider credentials and configuration, including plugin-specific or custom `key_env` variables, must be set in the Profile or its Hermes home. This applies to model discovery and normal turns alike; explicit Profile variables can also supply credentials needed by other tools. The station lists at most 50 discovered model IDs, prioritizing the current model and those named in config.json; every listed one runs, as do those named. Environment profiles also allow adding a model by name. Hermes 0.22 can prepare a separate dependency environment for a fresh profile before answering ACP; initialization gets up to ten minutes, while later requests retain their normal deadline. A probe refused because another launch holds the update lock and no dependency generation is committed retries for up to two minutes. An unconfigured profile still needs its own provider and default model; configuration errors are not retried. A failed probe keeps the last model list and existing selections and explains that the profile's provider configuration needs checking. A newly created, unconfigured Hermes home cannot inherit the machine's credentials silently.

Clients advertise their runtime vocabulary with the `stillfail-runtimes` request header. Requests without it retain the pre-Hermes vocabulary. The station filters unsupported profile/session metadata in the overview, lists, incremental refreshes, batch answers and live/replayed events; opening an unsupported session's execution detail returns an update-required error. Conversation text is kept, and an unknown agent is never relabelled as Claude or Codex. Old clients can continue using the station's supported runtimes; selecting Hermes requires an updated client. The response projection happens after idempotency caching, independently for each requesting client.

## Sessions and tools

- Initialize ACP, then `session/new` or `session/load`, with the session's working directory and the still.fail HTTP MCP server. Its bearer token is supplied as an HTTP header, never embedded in the prompt.
- If a model is selected, wait for `session/set_model` to succeed before accepting a turn. Leave it unset to use Hermes' default.
- Each `session/prompt` contains the station's instructions as an explicit context block followed by the incoming message. ACP has no portable system-prompt parameter; these are prompt context, not a replacement for Hermes' system prompt. The context names the station's shared memory and skills; shared skills are also linked into the profile's Hermes home. Nothing is written into the user's project.
- Text, thoughts and tool calls stream through `session/update`. Hermes adds an argument preview to a tool's display title; the driver separates it from the tool name and normalizes Hermes 0.22's `mcp__editor_stillfail_<hash>__…` names back to the station namespace, so live views, history and disconnection detection recognise station tools. The prompt's response ends the turn. `session/cancel` interrupts it. Messages arriving during a turn stay queued in still.fail: Hermes versions differ in how concurrent prompts redirect or queue work.
- Permission requests select `allow_once` only, matching the station's unattended agent execution without creating permanent Hermes allowlist entries. Unsupported client requests return a protocol error rather than hanging.
- Runners preserve running processes across station handover. Snapshots keep partial text and unfinished tools. Crash adoption reconstructs them from acknowledged ACP output. Loading a native session ignores the history replay so it is not recorded twice.

The station keeps its readable transcript at `<profile home>/hermes/sessions/<id>.jsonl`, using the same record format as Cursor and Devin. History and live views read it through the common transcript readers. Hermes' native conversation remains in that profile's `state.db`; resuming it requires the same Hermes home. Cross-profile migration of that native database is not implemented. ACP context estimates are not reported as billable token counts.

## Validation

```sh
node scripts/native.ts run runner mesh archive-rs -- node --test station/test/hermes.test.ts
node scripts/native.ts run runner -- node station/test/hermes-smoke.ts
```

The first runs a strict fake ACP peer under the real runner, covering tools, model selection, instructions, cancellation, failure classification, resumption, handover and crash adoption, including a pending station tool that disconnects during recovery. The second requires an installed Hermes with ACP and MCP and uses a temporary isolated Hermes home, a local deterministic OpenAI-compatible server and a local MCP endpoint. It checks authenticated tool execution, two completed turns, the previous messages in a resumed model request, and readable history without duplicates. It does not call a paid model or use an existing account.
