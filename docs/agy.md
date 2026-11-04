# Antigravity CLI (agy) as a runtime

`agy` is Google's coding CLI ([antigravity.google/cli](https://antigravity.google/cli)), a native binary installed into `~/.local/bin`. Since 2026-06-18 it is how a Google AI Pro or Ultra subscription (and a free Google account's weekly allowance) is used from a terminal: Gemini CLI no longer takes those accounts. The driver is `station/src/agents/agy.ts`; the fake the tests run it against is `station/test/fake/agy.mjs`. Pinned against agy 1.4.12.

## How it is driven

- One `agy acp --gemini-dir <profile home>/agy/.gemini --dangerously-skip-permissions --disable-telemetry` per session, under a runner whose id is the session key's, spoken to in ACP (`acp.ts`). `agy acp` is the CLI's own ACP server (not in its `--help`: `agy acp --help` lists its flags). Its `initialize` says `_meta.antigravity.systemPrompt.append` and session load, resume and list.
- `--gemini-dir`: every file of it (sign-in, settings, MCP servers, conversations, logs) in the profile's home, none of the machine's `~/.gemini`. `--dangerously-skip-permissions`: no approvals, as the other runtimes run here (a `session/request_permission` still asked is allowed for that call only). `AGY_CLI_DISABLE_AUTO_UPDATE=1`: it does not update itself in the background while sessions run.
- `session/new` (it names the conversation) or `session/load`, with the station's tools as an HTTP MCP server and the station's instructions as `_meta.antigravity.systemPrompt.append`. Their answer lists the models (`models.availableModels`, `currentModelId`); another is `session/set_model`, in the running process between turns too (`retune`).
- A turn is `session/prompt`, answered when it ends with its `stopReason` and `usage` (`inputTokens`, `cachedReadTokens`, `outputTokens`, `thoughtTokens`). What comes while it runs waits for the next turn. `usage_update` says the context used and the model's window.
- Failures: `Authentication required` (session/new, signed out), `Authentication expired. Please log back in.`, `RESOURCE_EXHAUSTED` (its allowance spent).

## Which profiles run it

- **A Gemini key** (api-provider `google`): given as `GEMINI_API_KEY`, besides DeepSeek Harness on the provider's chat endpoint.
- **Custom variables**: its own configuration (`GEMINI_API_KEY`, or a sign-in already in the profile's `agy/.gemini`).
- **A Google account** (the subscription): not offered yet. `agy` has no login command: it signs in in its TUI (`HOME=<profile home>/agy agy`, the "Google OAuth" choice), which over SSH (or with `SSH_CONNECTION` set) prints a link and takes back the code the page shows; its ACP `authenticate` only opens a browser with a loopback redirect, and refuses in an SSH session. On macOS it keeps the sign-in in the keychain unless it finds it unreachable or the session remote. Where that sign-in lands for a profile, and how the pages carry it, is to be pinned against a real sign-in first.

Google suspends accounts whose Antigravity sign-in is used by other tools (OpenClaw, OpenCode, 2026-02): the station only ever runs the CLI itself, never its sign-in or API on its own.

## History and usage

Its own conversations are its files (protobuf), not read here: the station keeps the transcript (`acp.ts` KeptTranscript) at `<home>/agy/sessions/<id>.jsonl`, read as Cursor's (`read/transcript.ts`), with each turn's usage as a `usage` line (input less the cache's read, thoughts with the output) that `usage/counter.ts` counts.

## Installing and updating

Installed by the person (its installer also writes the shell profiles: `install.sh --dir` still runs `agy install`). Updated with `agy update`. It says its latest version only to itself, so the station shows none.
