# Antigravity CLI (agy) as a runtime

`agy` is Google's coding CLI ([antigravity.google/cli](https://antigravity.google/cli)), a native binary installed into `~/.local/bin`. Since 2026-06-18 it is how a Google AI Pro or Ultra subscription (and a free Google account's weekly allowance) is used from a terminal: Gemini CLI no longer takes those accounts. The driver is `station/src/agents/agy.ts`; the fake the tests run it against is `station/test/fake/agy.mjs`. Pinned against agy 1.4.12.

## How it is driven

- One `agy acp --gemini-dir <profile home>/agy/.gemini --dangerously-skip-permissions --disable-telemetry` per session, under a runner whose id is the session key's, spoken to in ACP (`acp.ts`). `agy acp` is the CLI's own ACP server (not in its `--help`: `agy acp --help` lists its flags). Its `initialize` says `_meta.antigravity.systemPrompt.append` and session load, resume and list.
- `--gemini-dir`: every file of it (sign-in, settings, MCP servers, conversations, logs) in the profile's home, none of the machine's `~/.gemini`. `--dangerously-skip-permissions`: no approvals, as the other runtimes run here (a `session/request_permission` still asked is allowed for that call only). `AGY_CLI_DISABLE_AUTO_UPDATE=1`: it does not update itself in the background while sessions run.
- `session/new` (it names the conversation) or `session/load`, with the station's tools as an HTTP MCP server and the station's instructions as `_meta.antigravity.systemPrompt.append`. A call to an MCP tool is titled `Run mcp_<server>_<tool>`: the station's are named as the other runtimes name them (`mcp__stillfail__chat_post`), so the live steps, the history and losing the station's tools know them. Their answer lists the models (`models.availableModels`, `currentModelId`); another is `session/set_model`, in the running process between turns too (`retune`).
- A turn is `session/prompt`, answered when it ends with its `stopReason` and `usage` (`inputTokens`, `cachedReadTokens`, `outputTokens`, `thoughtTokens`). What comes while it runs waits for the next turn. `usage_update` says the context used and the model's window.
- Failures: `Authentication required` (session/new, signed out), `Authentication expired. Please log back in.`, `RESOURCE_EXHAUSTED` (its allowance spent).

## Which profiles run it

- **A Google account** (the subscription: Google AI Pro / Ultra, or a free account's allowance; Accounts → Add account → Google Gemini → 订阅 · Google AI): a `subscription` profile with `runtime: "agy"`. `agy` has no login command: it signs in in its TUI, which the station runs in a terminal of its own (platform.terminal, as Devin's) with the profile's `agy/` as its `HOME`. Not signed in, it asks how to sign in (the station answers its first choice, "Google OAuth"), prints a link at accounts.google.com (its redirect antigravity.google's page, which shows a code) and reads the code back, which the person pastes in the card (LoginManager, as Claude's). With that `HOME` it keeps the sign-in in a file, `agy/.gemini/antigravity-cli/antigravity-oauth-token` (`id_token_email` whose account it is), which the ACP server reads from `--gemini-dir`: each profile its own account. It goes on into its interface once signed in, so the sign-in is done once that file is written, and the command and the processes between (macOS: a shell, `cat`, script) are ended; if it is not written within 90 s of the code, the sign-in fails. `SSH_CONNECTION` is not passed on: in a remote session it first asks the terminal what it can do and waits for an answer the station's terminal never gives. (Its ACP `authenticate` only opens a browser with a loopback redirect.) Checked by that file (signed out without it); whether it works, and its models, a session opened only to ask says. Its allowance is not said to programs; not lent to other stations. Pinned against a real sign-in of a Google AI account with 1.4.12: signed in through the station's sign-in, checked, and a turn on it calling the station's `chat_post` (`station/test/agy-smoke.ts`, run by hand: it signs a real account in).
- **A Gemini key** (api-provider `google`): given as `GEMINI_API_KEY`, besides DeepSeek Harness on the provider's chat endpoint.
- **Custom variables**: its own configuration (`GEMINI_API_KEY`, or a sign-in already in the profile's `agy/.gemini`).

Google suspends accounts whose Antigravity sign-in is used by other tools (OpenClaw, OpenCode, 2026-02): the station only ever runs the CLI itself, never its sign-in or API on its own. Its terms forbid third-party software accessing the service even so; the plan's description where it is added says the account may be suspended.

## History and usage

Its own conversations are its files (protobuf), not read here: the station keeps the transcript (`acp.ts` KeptTranscript) at `<home>/agy/sessions/<id>.jsonl`, read as Cursor's (`read/transcript.ts`), with each turn's usage as a `usage` line (input less the cache's read, thoughts with the output) that `usage/counter.ts` counts.

## Installing and updating

Installed by the person (its installer also writes the shell profiles: `install.sh --dir` still runs `agy install`). Updated with `agy update`. It says its latest version only to itself, so the station shows none.
