# Working on still.fail cloud (for agents)

- It keeps only what is about people: accounts and sign-in, workspaces, members and roles, invitations, the list of a
  workspace's stations, each whole or one that only runs tasks (a rig, listed with the member whose it is; who may
  use it is that member's signature, checked by the machine, never the cloud's to say; listing it as the other kind
  changes nothing on the machine by itself, `station/AGENTS.md`), members' credentials and their revocation,
  still.fail's relays. A workspace's own relays and the ways it turned off are its stations'
  (`station/src/mesh/ways.ts`): what is kept of them here is for the stations and devices from before, and told to
  stations once as their first. A station's chats, sessions, runtime accounts and usage are the station's; the cloud
  never holds them nor passes a request on to a station (the root AGENTS.md, No way into a station from outside).
- Workers, each deployed on its own (`deploy.py` lists them, `wrangler*.jsonc` route them): the API
  (`src/index.ts`), the relay (`src/relay-worker.ts`: deploying it drops every relay connection, so it is deployed
  only when it changed), the static web, admin, preview, status and site. Their names, Durable Objects, bucket and
  secrets keep their names from before the rename: a renamed one would be new and empty.
- `src/directory.ts` (one SQLite Durable Object, `primary`) is who belongs where, every change one transaction: the
  rows stay together, as splitting them would make most changes span objects. What grows with devices, stations or
  requests is kept off it: a device's `/v1/events` socket is on its account's object (`src/account.ts`, also its
  sessions and whether it is let into the test channel), a station's presence socket on the station's own
  (`src/station.ts`, also whether it is enrolled). After each change the Directory tells those objects from an outbox
  (in order, again until it gets there); whatever keeps someone's access is awaited before the answer.
  `DIRECTORY_SOCKETS=primary` puts the sockets back on the Directory, the way back while nothing else depends on the
  objects. Whether a station is up is not the cloud's to say: devices find out over the mesh.
- A member's credential is a JWT the cloud signs (Ed25519, 30 days, bound to the device's key); stations check it
  offline with the key the presence socket's `state` frame gives, so a signed-in device works with the cloud down.
  A workspace in safe mode (the lock, `src/lock.ts` over `station/src/cloud/lock.ts` and `rules/`, kept as a station
  keeps it by `station/src/cloud/log-keep.ts`) is decided by
  what its owners signed, not by the cloud: the cloud cannot add people or stations to it. It and the personal lock
  are kept here only for the stations and devices from before the stations carried them (the root AGENTS.md, The
  cloud is the account system): nothing new that is not the account system comes here. Once a chain moved (`moved`
  its last entry) whether it is on is said in its root's log, never here: its `locked` stays true for those from before,
  and nothing here refuses by it as if it knew (`enroll`; the stations and the core go by the lock they hold).
- One cloud answers as the other product too (`src/guests.ts`; the user, 2026-11-12: still.fail's accounts move into
  monoid's cloud, both apps staying, each its own name): still.fail's hosts stay in still.fail's account, its API
  Worker forwarding there (`FORWARD_TO`), monoid's answering a forwarded request as still.fail's (`GUESTS`, under
  `FORWARD_SECRET`). The move itself is `src/move.ts`, run by `.github/workflows/move-cloud.yml`.
- `selfhost/` runs the same Workers on workerd outside Cloudflare (its README.md). Its config is made from the
  wrangler files, so a Worker, Durable Object, var or route added there is self-hosted too; a binding of a kind it has
  no stand-in for (only R2 and send_email have one) needs one there. Whatever names the cloud stays a var, never a
  host written in code: a self-hosted cloud's names are only known as it runs. `pnpm side` (side/selfhost.test.ts,
  the side run's) runs it on workerd for real, signing in through an SMTP relay and an OpenID provider.
- The control plane's contract is shared with Comma (AFK-surf/Cue): `station/src/cloud/provider.ts` holds what differs.
  A change to a station-facing route keeps both working.
- Tests run in Miniflare with everything outside mocked: `pnpm run types && pnpm run check && pnpm test`, one file
  `pnpm exec tsx --test test/<file>.test.ts`. What the Directory tells after a change answers is waited for with
  `h.settled()` (test/harness.ts), never a while; a socket is read after `h.heard(ws)`, never after a ping of a
  test's own (what a station says on its socket is answered by a call to the Directory, later than a pong).
  `test/dev.ts` runs every Worker locally (`docs/development.md`). Deploying is main's pipeline's, never by hand
  from a branch.
