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
- The connection gone (the station ended the process, the network broke), the far side ends the program's process
  group. A turn in flight then fails as a runtime that exited; its session starts again with `--resume`.
- A session's processes and its jobs share one sandbox, named from the session's key (`sandboxName`, at most 31
  characters, `s-…-<hash>`). Codex's host is shared by a profile's sessions and so runs in the profile's.

Not sent: a job with a port (a web service, reached here through the station) and a task that uses the screen.

## Sizes

`job_start` takes `cpus`, `memory_gib` and `disk_gib`. Such a job runs in a sandbox of its own of that size, named from
the session's key and the size, which the bridge first asks the front door to make (`create NAME --cpus N --mem GIB
--disk GIB`; l4es refuses more than its operator allows). A running sandbox cannot grow: l4h reserves a guest's memory in
full when it is made. Agents are told to ask a person in the chat before asking for one.

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
- The station's machine is still one place: if its sandbox goes, the station goes with it until it is started again.
