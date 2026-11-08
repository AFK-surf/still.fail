# Working on still.fail (for agents)

The apps have their own rules in `apps/mbui/AGENTS.md`; these apply to the whole repository.

## No polling between still.fail's own parts

The client core (`client/core-ts`), the station (`station/`) and the cloud (`cloud/`) never read something of another
of them again on a timer to see whether it changed. The part that owns it tells the others when it changes: an event on
a socket it already keeps (the cloud's `/v1/events` and a station's presence socket, `cloud/src/types.ts`), or a stream
it serves (a station's event stream). A reader reads when it is told, when it is first shown, and when its connection
opens again; a long poll is no exception: serve a stream.

A timer is only for what tells nothing by itself:

- a heartbeat or a ping that keeps a connection, or measures it;
- a sample of this machine (CPU, memory, the network's counters);
- a retry after a failure, with a backoff, and a timeout or deadline;
- a debounce of a burst;
- an outside system that offers no push (a registry, a provider's quota, a third party's feed).

`scripts/check.sh` refuses a timer a change adds to those three parts unless its line says which of these it is with
`timer:`. Removing an old part's support (a station from before an event) is better than polling it.

## No way into a station from outside

still.fail has no public entrance. A station is reached only on the mesh (`station/src/mesh/`): the iroh endpoint,
which admits the other stations of its workspaces by their keys and members by the credentials still.fail cloud signs.
Everything else a station listens on is this machine's own (127.0.0.1, a Unix socket, a socket the launcher holds for
it), and nothing makes it otherwise: no setting of the address, no tunnel (Tailcat, ngrok, cloudflared, a Tailscale
funnel), no port forward, no webhook for a platform to call. A station connects out to what it works with (still.fail
cloud's presence socket and relays, Slack's Socket Mode, Feishu, Comma) and is told over those connections.

The cloud (`cloud/`) keeps accounts, workspaces, member credentials and the relays; it takes no request for a station to
pass on to it, and the conversations do not go through its database. What spans a workspace (what an outside program
reads of it or does in it, its chats and usage brought together, a task sent to one of its stations) is the stations'
own: a station serves it, reaching the others over the mesh.

`scripts/check.sh` refuses a socket a station listens on that does not say 127.0.0.1 (or the fd, the path) on its line,
and any tunnel's name in the station or the cloud.
