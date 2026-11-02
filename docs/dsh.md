# DeepSeek Harness (dsh) as a runtime

A station runs Claude Code, Codex, DeepSeek Harness and Grok Build (docs/grok.md); this is DeepSeek Harness (`dsh`, [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness), npm `@deepseek-ai/dsh`, Node 22.19 or newer). The driver is `station/src/agents/dsh.ts`; the fake the tests run it against is `station/test/fake/dsh.mjs`.

## How it is driven

- One `dsh --profile acp --patch <file>` per session, under a runner whose id is the session key's (like Claude Code). The patch turns dsh's ACP server off and loads the station's own driver plugin, `station/src/agents/dsh-bridge.mjs` (a Cordis plugin, by its absolute path; the build copies it beside the bundle). dsh's own ACP and SDK servers do not do: neither takes input for a running turn, and the SDK cannot stop one.
- The plugin speaks a line of JSON per message (its header): `open` (dsh names the session, or resumes one), `prompt` (`agent.followup`: the next turn), `steer` (`agent.steer`: the running turn, read after the step it is in, so a tool call ends first), `cancel` (`agent.cancel`: the turn ends aborted). It sends the session's `turn/start`, `turn/end`, `tool/call`, `tool/result` events and the model's stream (`agent/assistant-stream`: text, thinking and a call's input as they come). `LiveFromDsh` (agents/live.ts) makes them live steps.
- The plugin imports nothing of dsh's: loaded from the station's directory, dsh's packages do not resolve there. It is plain JavaScript on dsh's internal agent API (`ctx.agents`, `followup`/`steer`/`cancel`, the `session/event` and `agent/assistant-stream` events), not a stable protocol: a dsh release may need it changed.
- The station's tools are dsh's own `@deepseek-ai/dsh-mcp-client`, inserted by the patch, the bearer token read from `STILLFAIL_MCP_TOKEN` (a `!!js` value: never in the file). `DSH_PERMISSION_MODE=danger-full-access`: no approvals are asked.
- A dsh whose plugin failed to load never answers `open`: the driver gives up after two minutes.

## Configuration

dsh's configuration is a stack of patches over its shipped `acp` profile (`dsh --profile acp --dump-default-config` shows it). The station writes one more per session, in `<profile home>/stillfail/<hash of the session key>.patch.yml` (JSON, which is YAML), from `dshPatch`:

- the profile's provider as a route: DeepSeek's own API on dsh's `deepseek-official` route (`llm-deepseek`, key in `DEEPSEEK_API_KEY`); any other on a pi-ai route named `stillfail` (`llm-pi-ai`) with the protocol the provider speaks, chat completions first, then Anthropic's, then Responses; key in `STILLFAIL_DSH_KEY`. A pi-ai route needs its model named.
- the model (`agent-default-model`, and the route the plugin's `open` asks for), the effort (`low`/`medium`/`high`/`max`; DeepSeek's route takes `low`, `high`, `max`); a pi-ai model known to read images (`accounts/models.ts` `seesImages`) is declared `input: ["text", "image"]`, so dsh's image tools read one for it — without the declaration dsh refuses every image, saying to switch models, whatever the model can do,
- the station's instructions as the system prompt's `personaSuffix`, with no prompt variables (the ACP server's `{{model}}` has no value without it; `{{` in the instructions is broken with a zero-width space: dsh's variables are strict),
- transcripts uncompressed under `<profile home>/dsh-sessions` (not dsh's own `sessions/`: a profile home's is Codex's too).

A profile of custom variables keeps dsh's own configuration (DeepSeek, `DEEPSEEK_API_KEY` from its variables). `DSH_HOME` is the profile home (the workspace's memory comes with the instructions, its skills are linked where the session runs, docs/multi-workspace.md), `DSH_AGENTS_HOME` a directory in it (not the person's `~/.agents`), `DSH_TELEMETRY_MODE=DISABLED`.

## Which profiles run it

dsh speaks every protocol the providers do, so an API provider's profile runs it whenever the provider has any endpoint (providers.ts `runtimesOf`): the chat-completions-only providers (DeepSeek, Kimi, Qwen, Gemini, Groq…) run dsh and nothing else. An OpenCode Go key runs all three runtimes, an Anthropic key Claude Code and dsh. dsh has no subscription here and no machine login.

## Not installed

dsh comes with no subscription, so a station may well not have it while its profiles offer it. A runtime is not looked for before a chat picks it: the start finds it. The runner's program is looked for on its PATH first (agents/runner.ts `CommandMissing`, for every runtime): one not there ends the start with the notice `无法启动 agent：此 station 尚未安装 {name}`, recorded with the runtime (`entries.runtime`), and the person's message stays pending. The core puts installing it under the notice (present.ts `installView`, from the station's updates: a manager's button that is `software.update {id}`, how far it is, why it failed); once the install ends with it on PATH, the hub gives that runtime's sessions what waits (`Hub.installed`).

## History and usage

`read/transcript.ts` finds `<home>/dsh-sessions/<cwd>/<id>/session.v<N>.jsonl` (the highest N) and reads `user/message` (only `source.kind = user`: dsh adds its runtime context as user messages too), `assistant/message` (`text`, `reasoning`, `tool-call`) and `tool/result`. Usage is `assistant/message`'s `data.usage` (input apart from the cache's read and written).
