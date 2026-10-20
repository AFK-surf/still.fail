# A station's variables for its agents

A station's owners and admins can set environment variables for everything the station starts for its agents: an
HTTP proxy the machine's network needs, mostly (`HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`). They are kept in config.json
as `agentEnv` (a map of names to one-line strings), read by `station/src/ops/agent-env.ts`.

## Where they go

- The runtimes (Claude Code, Codex, dsh), the profiles' sign-ins, the machine's command-line logins (docs/remote-login.md),
  the CLIs a profile is checked with, and the agents' background jobs: `startEnv` (and `cleanEnv`, agents/runtime.ts) is
  the station's own environment with these over it, less what each scrubs. A profile's own variables go over them.
- With a proxy among them, this machine is kept out of it: `localhost,127.0.0.1,::1` are added to `NO_PROXY` and
  `no_proxy` (the agents reach the station's tools on loopback).
- The station's requests on a profile's behalf (a Claude login renewed, an allowance asked, a profile checked, a shared
  Codex login renewed, the automatic decisions' model, the OpenCode Console) go through the proxy named, by
  `profileFetch` (Node's own proxying, `https.Agent({proxyEnv})`, NO_PROXY honoured). The station's own traffic
  (still.fail cloud, Slack, relays, updates) never does: a wrong proxy cannot shut its pages out of where it is fixed.

## Changing them

- `PUT /agent-env` (core `agentEnv.set`), owners and admins only: `{text}`, all of them as a .env file's lines
  (`NAME=value`, blank lines, `#` comments, `export ` and quotes round a value taken; the last of a name kept; a secret
  left as the overview shows it, masked, keeps its value; a wrong line refused by its number, `parseEnvText`), or `{env}`, a
  patch (a string sets one, null removes it, one left out stays). The overview has them as `agentEnv` (by name, a
  secret's value masked: a name with KEY/TOKEN/SECRET/PASSWORD/AUTH, or a URL with a password), absent from a station
  from before them, whose page then has no such section.
- The pages edit them as text in the core's draft (`agentEnvForm`, client/core-ts/src/agent-env.ts; calls
  `agentEnv.form.open|edit|save|drop`): each line read as it is typed into parts (name, value, comment) the pages colour,
  a line the station would refuse marked with why and the draft not saved while there is one, a name given twice said.
- Once they change, every session's process takes them now if idle, else before its next turn (`Hub.everyChanged`);
  a Codex app-server's signature includes them, so it starts again once idle. Edited in config.json by hand, they apply to
  whatever starts next.
