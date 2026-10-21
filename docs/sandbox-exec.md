# Execution in sandboxes

A station can run what it starts for its sessions in sandboxes instead of on its own machine: each session's runtime
process (Claude Code, Codex's host, …) and its jobs run in that session's own sandbox, made on first use and deleted
after it has been idle. The station itself (its chats, store, door, Slack and Feishu connections, the clients' links)
stays where it is and is still one station to the people using it. The sandboxes are an [l4es](https://l4es.afk.surf)
deployment of [l4h-sandbox](https://github.com/AFK-surf/l4h-sandbox), reached over its SSH front door.

## Setting

`sandbox` in config.json, edited by the workspace's owners and admins with `PUT /admin/api/sandbox`:

```json
{ "sandbox": { "ssh": "{name}.WORKSPACE@l4es.afk.surf", "identity": "/path/to/key", "knownHosts": "/path/to/known_hosts", "persist": "/mnt/sf/stations/NAME", "idleMinutes": 10 } }
```

`{name}` is the sandbox's name; `identity` a key linked to an account that is a member of the l4es workspace;
`persist` a directory on storage the sandboxes keep (an l4es managed NFS mount), where the station's files there live,
so that a session's outlive its sandbox (without it they are on each sandbox's own disk, gone when it is deleted).
`"enabled": false` switches it off and keeps the rest. Switching on is refused unless a sandbox can be had and the
station's data directory made there at its own path (`checkReach`).

## No shared file system

The station and its sandboxes share no file system. In each sandbox the station's data directory is made at the same
path (a link into `persist`; sudo where its parent is not the sandbox user's), so paths mean the same on both sides, and
the bridge copies files over its connection:

| What | Which way | When |
|---|---|---|
| The runtime's home (settings, the station's instructions), without what the runtime makes as it runs and without its login | here → there | the process starts |
| The station's agent home (MEMORY.md, skills) | both ways, newer wins | the process starts; back as the agent changes it |
| Transcripts (Claude's `projects/`, Codex's `sessions/`) | there → here, what they gained | the process starts; as they grow |
| What the station puts in a session's workspace (`uploads/`, `station-back/`, `.stillfail-instructions.md`), the jobs' `stillfail-job` | here → there | the process or job starts; before each input, when it changed |
| A file the agent attaches (`chat_post` files and the like) | there → here | when it is attached |
| A job's output and exit code | there → here | as it runs (the job's shell here runs the bridge) |

Everything else of the workspace (checkouts, builds, what the agent writes) is the sandbox's alone. A subscription's
login stays here: each process there is lent a short-lived token, as a subscription borrowed from another station is
(Claude: `CLAUDE_CODE_OAUTH_TOKEN`; Codex: an auth.json without its refresh token, renewed under the running app-server).
Newer is by modification time (whole seconds, kept when copied) for whole files and by size for transcripts. Links
into the data directory are copied as links, others followed; a file over 64 MB, or more than 512 MB at a start, is
left out.

## How a program gets there

Every runtime starts its process through `startRunner` (agents/runner.ts), and every job through `Jobs.spawn`. With the
setting on, both start `agents/sandbox-bridge.mjs` in the program's place. The runner, the drivers and the jobs' log and
exit files are unchanged: the bridge stands in for the program here.

- The bridge runs `ssh <sandbox>.<workspace>@host` with its far side given on the command line (nothing is installed in
  the sandbox), and sends the program, its arguments, environment and working directory. The sandbox keeps its own
  `HOME`, `USER` and the like; the station's `PATH` comes first. A program named by a path the sandbox does not have is
  found by its name there (the image's `claude`, `codex`).
- One exec channel carries everything, because the front door forwards no ports: the program's stdin, stdout, stderr
  and exit, and each TCP connection it makes to the station's door (`127.0.0.1:<port>`, MCP and job notices), which the
  far side listens for at the same port in the sandbox.
- A session's processes and its jobs share one sandbox, named from the session's key (`sandboxName`, at most 31
  characters, `s-…-<hash>`). Codex too: in sandboxes each session has an app-server of its own (codex.ts `hostKey`),
  ended with its thread, instead of one shared by a profile's sessions.

## Stopping

The station stops a session's sandbox itself rather than leave it to l4es's idle timeout: once the session's runtime
process has been idle (no turn, no wait) for `sandbox.idleMinutes` (10 by default), the process is ended, whatever its
runtime (no warm limit, Codex's too), and the sandbox deleted through the front door (`rm NAME`). The front door
refuses while anything still has a connection to it (a job of the session, a process started since): it stays then,
and goes after the agent's next idle spell (a job's end wakes the agent). A sandbox of a job's own size goes when that
job ends. What the sandbox had on its own disk goes with it; the session's files in `persist` stay, and the next
message resumes the conversation in a new one (`--resume`). A profile's own Codex app-server (its account's limits and
models) runs on the station's machine.

## A connection lost

- Each side pings the other every 10 s and takes the connection as lost after 30 s without a frame. The front door does
  not notice a station gone without a word (a half-open connection), and the sandbox's sshd only watches the front door;
  without this, the far side could run on until TCP gives up.
- The connection gone (the station ended the process, the network broke, the sandbox died), the far side ends the
  program's process group. Before it starts a runtime's process, it ends every runtime process group an earlier bridge
  started in that sandbox (one sandbox, one runtime: a session's), so that one left by a lost connection never runs
  beside the new one on the same transcript.
- Here the bridge tells a connection lost after the program started (`CONNECTION_LOST` on stderr, exit code 75) apart
  from the program ending and from a sandbox that could not be reached. A turn that fails so goes on once, its runtime
  started again with `--resume` and told what happened (`GO_ON_AFTER_LOST`, as after an authentication error); lost
  again, it is said in the chat. A job is started again once (its `.lost` file beside its exit file).
- The station's own machine is not looked after: if its sandbox goes, the station goes with it until it is started
  again. Its data is on NFS.

Not sent: a job with a port (a web service, reached here through the station) and another station's task (its files are
mirrored here, jobs/remote.ts).

## Sizes

`job_start` takes a `size`: one of the sizes the sandboxes' operator names (l4es `SBX_SANDBOX_SIZES`, listed by
`ssh _@host help`). Such a job runs in a sandbox of its own of that size, named from the session's key and the size,
which the bridge first asks the front door to make (`create NAME --size SIZE`; l4es refuses a name it does not have). A
running sandbox cannot grow: l4h reserves a guest's memory in full when it is made. Agents are told to ask a person in
the chat before asking for one.

## Other stations' tasks

`station_task` jobs from other stations run on the station's own machine, as before: their files are mirrored here.

## Measured (2026-10-21, l4es, sandboxes of 2 vCPU and 4 GiB)

| | |
|---|---|
| A new sandbox, from the first SSH connection | about 3 s from inside l4es, 6 s from a machine outside it |
| A session's first turn, its sandbox made and claude started | 4.1 s |
| A turn with an MCP call back to the station | 0.24 s |
| A new exec on an existing sandbox, from a machine outside l4es | 2.0 s |

Copying files (2026-10-21, the station on a VM in Tokyo, the sandbox in Los Angeles): a line a transcript gained there is
here within about 1.5 s; bringing one attached file, or copying new uploads before an input, about 3 s (a connection of
its own); nothing new to copy, no connection.

## Not yet

- The setting has no page in the clients: it is config.json and the admin API.
- The files page and `station_task`'s `dir` see the workspace as it is here: what the agent made in its sandbox is not
  there.
- Runtimes other than Claude Code and Codex get their home copied there, not their transcripts back.
- Services (jobs with a port) and screen tasks stay on the station's machine.
- The station's own machine has no recovery: a sandbox of the station's that goes takes the station with it until it
  is started again.
