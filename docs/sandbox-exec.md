# Execution in sandboxes

A station can run what it starts for its sessions in sandboxes instead of on its own machine: each session's runtime
process (Claude Code, Codex's host, …) and its jobs run in that session's own sandbox, made on first use and deleted
after it has been idle. The station itself (its chats, store, door, Slack and Feishu connections, the clients' links)
stays where it is and is still one station to the people using it. The sandboxes are an [l4es](https://l4es.afk.surf)
deployment of [l4h-sandbox](https://github.com/AFK-surf/l4h-sandbox), reached over its SSH front door.

## Setting

`sandbox` in config.json, edited by the workspace's owners and admins with `PUT /admin/api/sandbox`:

```json
{ "sandbox": { "ssh": "{name}.WORKSPACE@l4es.afk.surf", "identity": "/path/to/key", "knownHosts": "/path/to/known_hosts" } }
```

`{name}` is the sandbox's name; `identity` a key linked to an account that is a member of the l4es workspace.
`"enabled": false` switches it off and keeps the rest. Switching on is refused unless a sandbox sees the station's data
directory at the same path (`checkReach` writes a file here and reads it there): the station's data directory must be
on storage its sandboxes mount too, in practice an l4es managed NFS mount, with the station on a machine that mounts the
same export at the same path (an l4es sandbox created with `create NAME --keep`, so it is not deleted when idle).

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

Not sent: a job with a port (a web service, reached here through the station) and a task that uses the screen.

## Sizes

`job_start` takes a `size`: one of the sizes the sandboxes' operator names (l4es `SBX_SANDBOX_SIZES`, listed by
`ssh _@host help`). Such a job runs in a sandbox of its own of that size, named from the session's key and the size,
which the bridge first asks the front door to make (`create NAME --size SIZE`; l4es refuses a name it does not have). A
running sandbox cannot grow: l4h reserves a guest's memory in full when it is made. Agents are told to ask a person in
the chat before asking for one.

## Other stations' tasks

`station_task` jobs from other stations go through the same bridge, in a sandbox per source session. They do not wait
in the station's queue (jobs/admit.ts), which measures this machine: l4es places the sandbox where a node has room.

## Measured (2026-10-21, l4es, sandboxes of 2 vCPU and 4 GiB)

| | |
|---|---|
| A new sandbox, from the first SSH connection | about 3 s from inside l4es, 6 s from a machine outside it |
| A session's first turn, its sandbox made and claude started | 4.1 s |
| A turn with an MCP call back to the station | 0.24 s |
| A new exec on an existing sandbox, from a machine outside l4es | 2.0 s |

## Not yet

- The setting has no page in the clients: it is config.json and the admin API.
- Services (jobs with a port) and screen tasks stay on the station's machine.
- The station's own machine has no recovery: a sandbox of the station's that goes takes the station with it until it
  is started again.
