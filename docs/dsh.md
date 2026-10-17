# DeepSeek Harness (dsh) as a runtime

A station runs three runtimes: Claude Code, Codex and DeepSeek Harness (`dsh`, [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness), npm `@deepseek-ai/dsh`, Node 22.19 or newer). The driver is `station/src/agents/dsh.ts`; the fake the tests run it against is `station/test/fake/dsh.mjs`.

## How it is driven

- One `dsh --profile acp --patch <file>` per session, under a runner whose id is the session key's (like Claude Code). It speaks [ACP](https://agentclientprotocol.com) (JSON-RPC over stdio): `initialize`, then `session/new` (dsh names the session) or `session/resume`, `session/prompt` per turn (answered when the turn is over: `stopReason`, or an error whose message says why), `session/cancel`.
- What the model says comes whole in `session/update` (`agent_message_chunk`, `agent_thought_chunk`), not as it streams; tool calls as `tool_call` then `tool_call_update`. `LiveFromDsh` (agents/live.ts) makes them live steps.
- ACP takes one prompt at a time: `steer` says no, so a message for a running turn waits for the next. There is no way to move a call to the background.
- The station's tools are an HTTP MCP server given to `session/new`/`session/resume` with the session's bearer token. A permission dsh asks (it should not: `DSH_PERMISSION_MODE=danger-full-access`) is allowed.
- Prompt ids are `prompt:<uuid>`: whatever answers one ends the turn, so a station taking a session up after a crash needs no record of which prompt it sent.

## Configuration

dsh's configuration is a stack of patches over its shipped `acp` profile (`dsh --profile acp --dump-default-config` shows it). The station writes one more per session, in `<profile home>/stillfail/<hash of the session key>.patch.yml` (JSON, which is YAML), from `dshPatch`:

- the profile's provider as a route: DeepSeek's own API on dsh's `deepseek-official` route (`llm-deepseek`, key in `DEEPSEEK_API_KEY`); any other on a pi-ai route named `stillfail` (`llm-pi-ai`) with the protocol the provider speaks, chat completions first, then Anthropic's, then Responses; key in `STILLFAIL_DSH_KEY`. A pi-ai route needs its model named.
- the model (`acp` and `agent-default-model`), the effort (`low`/`medium`/`high`/`max`; DeepSeek's route takes `low`, `high`, `max`),
- the station's instructions as the system prompt's `personaSuffix` (`{{` broken with a zero-width space: dsh's prompt variables are strict),
- transcripts uncompressed under `<profile home>/dsh-sessions` (not dsh's own `sessions/`: a profile home's is Codex's too).

A profile of custom variables keeps dsh's own configuration (DeepSeek, `DEEPSEEK_API_KEY` from its variables). `DSH_HOME` is the profile home (its `AGENTS.md` and `skills/` are the station's shared memory and skills, agent-home.ts), `DSH_AGENTS_HOME` a directory in it (not the person's `~/.agents`), `DSH_TELEMETRY_MODE=DISABLED`.

## Which profiles run it

dsh speaks every protocol the providers do, so an API provider's profile runs it whenever the provider has any endpoint (providers.ts `runtimesOf`): the chat-completions-only providers (DeepSeek, Kimi, Qwen, Gemini, Groq…) run dsh and nothing else. An OpenCode Go key runs all three runtimes, an Anthropic key Claude Code and dsh. dsh has no subscription here and no machine login.

## History and usage

`read/transcript.ts` finds `<home>/dsh-sessions/<cwd>/<id>/session.v<N>.jsonl` (the highest N) and reads `user/message` (only `source.kind = user`: dsh adds its runtime context as user messages too), `assistant/message` (`text`, `reasoning`, `tool-call`) and `tool/result`. Usage is `assistant/message`'s `data.usage` (input apart from the cache's read and written).
