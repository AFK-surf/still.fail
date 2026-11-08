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
