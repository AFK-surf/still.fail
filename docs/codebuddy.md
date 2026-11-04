# CodeBuddy Code as a runtime

CodeBuddy Code is Tencent's coding CLI (npm `@tencent-ai/codebuddy-code`, commands `codebuddy` / `cbc`; docs at [workbuddy.ai/docs/cli](https://www.workbuddy.ai/docs/cli/overview)), the engine WorkBuddy's desktop app runs (its package ships a `codebuddy-lite-wb` build for it). The driver is `station/src/agents/codebuddy.ts`; the fake the tests run it against is `station/test/fake/codebuddy.mjs`. Pinned against 2.179.3.

## How it is driven

- One `codebuddy --acp --permission-mode bypassPermissions [--append-system-prompt <instructions>] [--effort <effort>]` per session, under a runner whose id is the session key's, spoken to in ACP (`acp.ts`). Its `initialize` says `loadSession` and HTTP MCP servers.
- `CODEBUDDY_CONFIG_DIR=<profile home>/codebuddy/.codebuddy`: its settings, sessions and logs in the profile's home, none of the machine's `~/.codebuddy`. `DISABLE_AUTOUPDATER=1`, `DISABLE_TELEMETRY=1`. The machine's `CODEBUDDY_API_KEY`, `CODEBUDDY_AUTH_TOKEN`, `CODEBUDDY_INTERNET_ENVIRONMENT` and endpoint variables are not passed on: only the profile's.
- `session/new` (it names the session) or `session/load` with `_meta["codebuddy.ai/suppressReplay"]: true` (it says nothing again of the past), with the station's tools as an HTTP MCP server. Its MCP tools are named `mcp__<server>__<tool>`, as Claude Code's. Their answer lists the models (`models.availableModels`, `currentModelId`); another is `session/set_model`, in the running process between turns too (`retune`). The effort is a flag: another effort starts the process again.
- A turn is `session/prompt`, answered when it ends with its `stopReason`. A message for the running turn is `session/steer` (`{sessionId, contentBlocks}`), answered `{steered: true}` once it is taken into the turn, `{steered: false, reason: "idle"}` when nothing runs (the station then starts the turn itself). `usage_update` says the context used and the model's window.
- Failures: `Authentication required` (`data.category: "auth"`) when no account is signed in or the key is refused.

## Which profiles run it

**Custom variables** (Accounts → Add account → 自定义变量 · CodeBuddy Code): `CODEBUDDY_API_KEY`, and `CODEBUDDY_INTERNET_ENVIRONMENT=internal` for the China site (copilot.tencent.com: keys at copilot.tencent.com/profile), unset for the international one (codebuddy.ai/profile/keys); or `CODEBUDDY_AUTH_TOKEN`. The check opens a session only to read its models, which also says whether it is signed in.

Not offered yet: signing in to a CodeBuddy / WorkBuddy account (WeChat, Google/GitHub, iOA, enterprise domain) from the station. The CLI keeps that sign-in in the machine's `~/Library/Application Support/CodeBuddyExtension` (Windows `%LOCALAPPDATA%\CodeBuddyExtension`, Linux `~/.local/share/CodeBuddyExtension`), under `HOME` rather than its config directory, so a profile without a key may run on whatever account that machine is signed in to (not verified yet).

## History and usage

The station keeps the transcript (`acp.ts` KeptTranscript) at `<home>/codebuddy/sessions/<id>.jsonl`, read as Cursor's (`read/transcript.ts`), with each turn's usage as a `usage` line where the prompt's answer says it.

## Installing and updating

Installed and updated with npm (`npm install -g @tencent-ai/codebuddy-code@latest`), as DeepSeek Harness and Grok Build are.
