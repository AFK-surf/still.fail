# Cursor as a runtime

A station runs five runtimes: Claude Code, Codex, DeepSeek Harness (docs/dsh.md), Grok Build (docs/grok.md) and Cursor, on the person's Cursor account. The driver is `station/src/agents/cursor.ts` with the station's own program beside it, `station/src/agents/cursor-bridge.mjs`, which runs Cursor's TypeScript SDK ([`@cursor/sdk`](https://cursor.com/docs/sdk/typescript), its local runtime: the agent loop on the station, the models Cursor's). The fake SDK the tests run it against is `station/test/fake/cursor-sdk/`. Pinned against `@cursor/sdk` 1.0.

## Why the SDK, not the CLI's ACP

The Cursor CLI (`agent acp`) speaks ACP too, but a `session/prompt` while a turn runs cancels the turn first: the command it runs is killed, and the model runs it again. The SDK's `run.steer(text)` puts the message in the running turn instead; a command running then goes on in the background and the model reads its output when it is done. The SDK also says each turn's usage (the CLI's ACP says none), takes the station's tools with their token, and takes a model per prompt.

## How it is driven

- One `node cursor-bridge.mjs` per session (the station's own Node: `process.execPath`), under a runner whose id is the session key's, speaking a line of JSON per message (the bridge's header): `open` (`Agent.create`, or `Agent.resume` of one it keeps), `prompt` (`agent.send`: a run is a turn), `steer` (`run.steer`, answered `delivered` or not; not delivered, the station gives it as the next turn's), `cancel` (`run.cancel`). It sends the run's messages as they come (`{ev: "message"}`: status, thinking, assistant text, tool calls, usage) and its end (`{ev: "end", status}`: finished, cancelled, error). `LiveFromCursor` (agents/live.ts) makes them live steps; an MCP tool is named as Claude Code names one (`mcp__stillfail__chat_post`).
- The station's tools are an HTTP MCP server (`mcpServers.stillfail`, the session's token in its Authorization header, read from `STILLFAIL_MCP_TOKEN`).
- The station's instructions are a project rule that always applies (`.cursor/rules/stillfail.mdc`) in a folder of the session's own (`<profile home>/cursor/station/<hash of the key>/`), given to the SDK as another workspace folder (`local.dirs`), with the skills of the session's workspace linked in as `.cursor/skills` (its memory is in the instructions, docs/multi-workspace.md). `local.settingSources` is `["project"]` only: the person's own project rules apply, not their Cursor account's user rules. (`systemPrompt` replaces Cursor's whole prompt and is gated by Cursor; ACP's `_meta.rules` is not read.)
- The SDK keeps its agents (their checkpoints, the terminals' output) under `os.homedir()/.cursor`: the bridge sets `os.homedir` (not `HOME`, which the commands the agent runs keep) to `<profile home>/cursor/sessions/home`, apart from the person's own Cursor.
- The model is the SDK's selection, said as Cursor says a variant: `id` or `id[param=value,…]` (`gpt-5.5[reasoning=high]`); none named, `default` (Auto). Another model between turns is the next prompt's (`retune`), no new process. Its efforts are in its models' variants: none apart (`fallbackEfforts` is empty).
- No approvals: the SDK's local agent runs its tool calls without asking.

## Signing in

A Cursor account is a `subscription` profile with `runtime: "cursor"`; custom variables (`CURSOR_API_KEY`) run it too. The sign-in (accounts/cursor.ts, `LoginManager.startCursor`) needs no command: the station makes the login page itself (`cursor.com/loginDeepControl?challenge=…&uuid=…`, the challenge a SHA-256 of a verifier only the station holds) and asks Cursor's backend (`POST /auth/poll`) until the person confirms it there; the page shows no code (`needs_approval` with `userCode` null). The login's session token is used once to mint a user API key (`DashboardService/CreateUserApiKey`, no expiry: unlike the SDK's own login, which mints one for 90 days) and dropped. The key, named `still.fail · <machine>`, is kept in `<profile home>/cursor/auth.json`; the person sees it in their Cursor dashboard's API keys and can revoke it there (the profile then asks to be signed in again). Checked with Cursor's API (`GET api.cursor.com/v1/me`, `/v1/models`, the key as basic auth). Cursor says no plan usage to a key: the allowance is `unsupported`. Not lent to other stations yet: sharing one is refused.

## Installed

The SDK is an npm package (`@cursor/sdk`, about 50 MB with its platform's binaries), installed and updated by the station's npm (where the machine has none, by a Node of nodejs.org's the station puts in `<data>/node` first, on the station's own PATH only: updates/runtimes.ts `ownNode`) into a prefix of its own, `<data>/runtimes/cursor` (`npm install -g --prefix …`: apart from the machine's global packages, and found by a look at the disk, `lib/node_modules/@cursor/sdk`). Not there, a start ends as a runtime not on PATH does (agents/runner.ts `CommandMissing("cursor")`), and the pages offer to install it.

## History and usage

The bridge keeps the transcript itself, `<profile home>/cursor/sessions/<agent id>.jsonl`: a line each of `user` (the prompt, or a message steered in), `assistant` and `thinking` (whole, as they were said in pieces), `tool` (a call and what it gave back), `usage` (the run's counts, input apart from the cache's read and written) and `end`. `read/transcript.ts` reads it for the history, usage/counter.ts and sessions/live.ts its `usage` lines. The SDK's own store (a database of checkpoints) is not read.
