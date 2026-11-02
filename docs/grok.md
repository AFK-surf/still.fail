# Grok Build (grok) as a runtime

A station runs four runtimes: Claude Code, Codex, DeepSeek Harness and Grok Build (`grok`, xAI's coding CLI, [xai-org/grok-build](https://github.com/xai-org/grok-build), npm `@xai-official/grok`, a native binary). The driver is `station/src/agents/grok.ts`; the fake the tests run it against is `station/test/fake/grok.mjs`. Pinned against Grok Build 1.0.62.

## How it is driven

- One `grok agent --always-approve --no-leader [--model M] [--reasoning-effort E] stdio` per session, under a runner whose id is the session key's (like Claude Code and dsh), spoken to in ACP (JSON-RPC over stdio). `--no-leader`: its own process, not the shared `~/.grok/leader.sock` backend; `--always-approve`: no approvals, as the other runtimes run here (a `session/request_permission` still asked is allowed for that call only).
- `initialize`, then `session/new` (Grok Build names the session, a UUIDv7) or `session/load` for one it has; both with the station's tools as an HTTP MCP server (`mcpServers`, the session's bearer token in its headers) and the station's instructions as `_meta.rules` (after Grok Build's own system prompt).
- A turn is `session/prompt`, answered when it ends: `stopReason` (`end_turn`; `cancelled` after `session/cancel`), its `_meta.usage`, or an error. What comes while it runs goes into it with `_x.ai/interject` (ACP extension methods have a leading `_` on the wire): read at the next safe point, after the tool call it is in. Not sent when nothing runs: Grok Build would make it a turn of its own.
- The model's text and thoughts stream as `session/update` `agent_message_chunk`/`agent_thought_chunk` with no id of their own; a call is `tool_call`, then `tool_call_update`s, the last `completed` or `failed` with its output (`LiveFromAcp`, agents/live.ts). Grok Build's own notifications (`_x.ai/session_notification`, `_x.ai/queue/changed`…) are not needed. A subagent's `session/update`s carry its own session id: left out.
- Another model or effort between turns is `session/set_config_option` (`model`, `reasoning_effort`) in the running process (`retune`), not a new one.
- A subagent it spawns is told on the parent's `_x.ai/session_notification` (`subagent_spawned` with its `child_session_id`, `subagent_finished`); its session's `session/update`s are shown as a subagent's steps, under the call that was running when it was spawned.
- An MCP server's tools are behind Grok Build's `search_tool` and `use_tool` (the tool's full name `server__tool`, its input inside). The instructions say to call the station's directly (`use_tool` with `stillfail__chat_post`), and the live steps and the history name such a call as Claude Code names an MCP tool, `mcp__stillfail__chat_post` (`acpCall`).

## Its home and configuration

`GROK_HOME` is `<profile home>/grok`: apart from the other runtimes a profile runs (Codex keeps its own `sessions/` in the profile home). Its `sessions/` are the shared transcripts (agent-home.ts); the workspace's memory comes with the instructions, its skills are linked where the session runs (docs/multi-workspace.md). `GROK_DISABLE_AUTOUPDATER=1`, telemetry off, and every Claude Code and Cursor compatibility cell off (`GROK_CLAUDE_*_ENABLED`, `GROK_CURSOR_*_ENABLED`: not the person's hooks, MCP servers, rules or skills). `~/.agents/skills` is always read by Grok Build (as by Codex).

## Which profiles run it

- **SuperGrok** (or X Premium+): a `subscription` profile with `runtime: "grok"`. Signed in with `grok login --device-auth` in its home (LoginManager, like Codex's device code: a link at accounts.x.ai with the code in it); Grok Build keeps the sign-in in `auth.json` and renews it itself. Checked with `grok models` (signed in or not, the account's models); its allowance is `_x.ai/billing` asked of a `grok agent stdio` started for it (the included credits used of the current, weekly or monthly, period; a zero is left out of the answer). Not lent to other stations yet: sharing one is refused.
- **An xAI key** (api-provider `xai`): Grok Build is given it as `XAI_API_KEY`, besides the runtimes its protocols run.
- Custom variables: Grok Build's own configuration.

## History and usage

`read/transcript.ts` finds `<home>/grok/sessions/<cwd, escaped>/<id>/chat_history.jsonl` and reads `user` (only those with a `prompt_index`: what the station said, unwrapped from `<user_query>`; not the context Grok Build adds, which has a `synthetic_reason`), `reasoning` (its summary), `assistant` (text and `tool_calls`) and `tool_result`. Its lines have no time. Grok Build keeps no usage in the session: the driver writes each prompt answer's `_meta.usage` beside the transcript (`stillfail-usage.jsonl`, input less the cache's read and written), which usage/counter.ts counts, with the context the turn ended with (the answer's `_meta.totalTokens`) and the model's window (`totalContextTokens` of the models session/new or session/load lists), which the history shows.
