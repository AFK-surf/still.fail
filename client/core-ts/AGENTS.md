# Working on the client core (for agents)

The core is every client's logic: the app on every platform runs it in Hermes (`apps/mbui/engine`, Apple's
`apps/mbui/src/host/apple_core.mm`), the web in a tab's worker (`src/hosts/web.ts`). The UIs send it named calls,
hold subscriptions to its topics and draw what it pushes; they never reach a station or the cloud themselves. Its
design rules (the user, 2026-10-03):

1. **Everything async is Effect**: calls, subscriptions, links, sockets, sync are fibers in scopes (`src/runtime.ts`);
   cancelling is interrupting; timers are the Clock's (a TestClock in tests), never `setTimeout`. `Host`
   (`src/host.ts`, made in `src/hosts/`) is what differs per platform, every operation an Effect.
2. **Pushed, never polled**: a station's `/events`, the cloud's `/v1/events`. Only a measure shown on screen (a link's
   speed, "waited 3 s") is sampled, while it is looked at.
3. **Cache first**: each signed-in account has its SQLite database (`src/data.ts`, `src/db/`), one writer, schema
   versioned and migrated. A topic is read from it by a query, never from the network.
4. **One sync owns all traffic** (`src/sync/scheduler.ts`, `src/station/sync.ts`, `src/sync/cloud.ts`): it keeps
   everything current by itself whatever is shown; what a UI shows or `client.focus` only raises priority. A
   subscription never starts a request. (Exceptions, read only while shown: a station's usage, its archived chats.)
5. **An action does not wait for the network**: it takes effect in the core at once (the outbox, a pending chat, the
   overlays of renames, pins, archives, kept in the database across restarts), `doing` tracks it, a failure rolls it
   back and says why. Something made here meets the station's by its exact `clientKey`, never by a guess.
6. **Changes are by key**: a topic's collections (`src/collections.ts`) recompute only the items whose records changed;
   an unchanged item is the same object, and a keyed subscriber gets insert, patch, drop, move ops.
7. **Workspaces are isolated** from each other.

## What a topic sends is bounded

The app parses every message of the core on its frame thread: on the owner's phone a `stations` of 463 KB took 25–86 ms
each time it came. So what a topic sends is bounded (the user, 2026-11-10): `test/topic-bytes.test.ts` measures every
way the app asks each topic on a workspace of real size (`test/real-size.ts`), a value sent whole at most 32 KB, a
message as something changes at most 4 KB. A list's item carries what its row shows; a page of one thing asks that
thing's own topic; a field one page needs is not added to a list every page holds; a new topic is placed in the test's
tables. Its `OVER` tables only fall. A topic the app lets go of keeping its value (`keep`) and asks again (`have`) is
sent `same`, or what changed from what it kept (store.ts `#first`), held to the change's bar too (`OVER_AGAIN`).

## What is shared is never written

Unchanged things being the same object is what makes rule 6 work, so a value read from the database
(`Data.shared()`), stored or computed in the store, sent out (`src/output.ts`) or kept in a cache is read-only from
the moment it is made. A function writes only on objects it made this time: copy at the level it changes
(`{ ...m, by: { ...m.by, here: true } }`, `[...a].sort()`), put back what did not change. Tests and the web's
development build deep-freeze shared values (`src/util.ts` `sharedValue`); `scripts/writes.ts` refuses writes on
parameters in the files that make views.

## Contracts made from here

- `src/ops.ts` `PARAMS` declares each operation's parameters; `scripts/operations.ts` writes the UIs' bindings from
  it. `src/shapes/schema.ts` declares what every topic gives; `scripts/shapes.ts` writes the clients' types and the
  app's `said` paths. Both are checked in and `--check`ed: change the source and run the script, never edit the output.
- Hermes 0.81 runs it: no `toSorted` and the like, no `Intl` outside `src/hosts/` (names are ordered by the host's
  `collate`). `scripts/hermes-bundle.ts` bundles it; a change that runs only in Node is not done.
- Tests: `pnpm test`, one file `node ../../scripts/native.ts run mesh -- node --test test/<file>.test.ts`; networks
  are simulated on the test's clock (`test/sim-iroh.ts`, seeds in `test/sim-seeds.ts`, `SIM_SEED=` runs one).
