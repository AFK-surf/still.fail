# Working on still.fail cloud (for agents)

- It keeps only what is about people: accounts and sign-in, workspaces, members and roles, invitations, the list of a
  workspace's stations, members' credentials and their revocation, the relays. A station's chats, sessions, runtime
  accounts and usage are the station's; the cloud never holds them nor passes a request on to a station
  (the root AGENTS.md, No way into a station from outside).
- Workers, each deployed on its own (`deploy.py` lists them, `wrangler*.jsonc` route them): the API
  (`src/index.ts`), the relay (`src/relay-worker.ts`: deploying it drops every relay connection, so it is deployed
  only when it changed), the static web, admin, preview, status and site. Their names, Durable Objects, bucket and
  secrets keep their names from before the rename: a renamed one would be new and empty.
- `src/directory.ts` (one SQLite Durable Object) is who belongs where, every change one transaction, and holds the
  sockets that make it live: a device's `/v1/events` and a station's presence socket, pushed what changed. Whether a
  station is up is not the cloud's to say: devices find out over the mesh. `src/account.ts` is one account's sessions.
- A member's credential is a JWT the cloud signs (Ed25519, 30 days, bound to the device's key); stations check it
  offline with the key the presence socket's `state` frame gives, so a signed-in device works with the cloud down.
  A workspace in safe mode (the lock, `src/lock.ts` over `station/src/cloud/lock.ts` and `rules/`) is decided by
  what its owners signed, not by the cloud: the cloud cannot add people or stations to it. It and the personal lock
  are kept here only for the stations and devices from before the stations carried them (the root AGENTS.md, The
  cloud is the account system): nothing new that is not the account system comes here.
- The control plane's contract is shared with Comma (AFK-surf/Cue): `station/src/cloud/provider.ts` holds what differs.
  A change to a station-facing route keeps both working.
- Tests run in Miniflare with everything outside mocked: `pnpm run types && pnpm run check && pnpm test`, one file
  `pnpm exec tsx --test test/<file>.test.ts`. `test/dev.ts` runs every Worker locally (`docs/development.md`).
  Deploying is main's pipeline's, never by hand from a branch.
