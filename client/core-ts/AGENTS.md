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
tables. A page's topic carries what the page draws; what shows only after a press is asked at the press, answered at
once from the device's data, and what it opens appears whole once that is there (the user, 2026-11-11): a chat list's
row and its menu (`chatRow`), a new chat's model control closed and its panel (`pick`). The test's `OVER` tables only
fall. A topic the app lets go of keeping its value (`keep`) and asks again (`have`) is sent `same`, or what changed from what it kept (store.ts `#first`), held to the change's bar too (`OVER_AGAIN`).
Every way of asking has a change measured, a cause of `test/real-size-asked.ts` `CAUSES` that changes what it shows as
the sync is told it, or is in the test's `STILL` with why its value does not change while shown, and `STILL` only
falls; what each cause sends is written for the app's sweep as the ops a device applies (`test/real-size-app.test.ts`,
`apps/mbui/src/sfrealsize/c_*.mbt`). What goes out is what the topic's shape declares, the rest dropped
(`src/conform.ts`), while the core's own readers read its whole value (`store.value`): a field the core reads and
no UI does stays out of the shape (a chat's agents' models,
which `src/choose.ts` reads of `views.agent`). A part a view shapes once for every topic that holds it (views.ts
`asShaped`) goes out as each topic's own shape says there (a station's overview to its page as `StationOverview`,
conform.ts `reshaped`); where one shape is sent by several topics and only some pages read a field, the others get a
shape of their own (`ListedProfile`, `StationProfile` beside `Profile`). The fixture fills every list and map a
weighed topic's shape declares: one left empty is listed in the test's `EMPTY` with why (an error or a state the
workspace is not in, a thing it has none of), and `EMPTY` only falls; a topic is left unweighed (`NOT_MEASURED`) only
with the bound that keeps it small named (a cap's constant, a fixed set of fields). A picture goes in no topic's
value: the value names it by a token and its bytes come beside a call's answer (a link's card's and a file's peek's:
`src/peek-pictures.ts`; a chat's: `station.file`).

## What answering reads follows what it sends

What answering a way of asking reads of the database follows what it sends, not how much the device holds (the owner,
2026-11-12: 「不应该这么无休止地扣细节」「这应该从架构设计和测试层面解决」, after two days of slow topics found one at a
time by hand). `test/topic-work.test.ts` counts, in the database's own calls, the bytes of text every way of `ASKED`
reads on a core started anew (and asked again), and each interaction the app sends (a start, a switch of workspace, a
chat opened, a place of the bar) to its first screen and to rest: at most twice what it sends or 8 KB, and with the
workspace's chats, messages, profiles, people or stations three times (real-size.ts `Size`, a worker thread a size), its
reading growing no faster than what it sends. Those over now are in its `OVER_READ`, `OVER_READ_AGAIN` and `GROWS`, which
only fall; a failure prints the statements that read most.

## What is shared is never written

Unchanged things being the same object is what makes rule 6 work, so a value read from the database
(`Data.shared()`), stored or computed in the store, sent out (`src/output.ts`) or kept in a cache is read-only from
the moment it is made. A function writes only on objects it made this time: copy at the level it changes
(`{ ...m, by: { ...m.by, here: true } }`, `[...a].sort()`), put back what did not change. Tests and the web's
development build deep-freeze shared values (`src/util.ts` `sharedValue`); `scripts/writes.ts` refuses writes on
parameters in the files that make views.

## A list's rows are kept beside their records

A chat list's row is kept beside its record (`chat_row`, `src/db/schema.ts` ensureListRows) under the key of what else
it is made with (`src/views/views.ts` listRowKey): kept as a list first reads it, and from then on made again as its
record is written, so a write costs by what lists showed, not by how many chats a station has (a chat no list read
has none made); the list's first answer reads those rows, no record (`test/list-rows.test.ts`; 2026-11-12). So `#listRow` reads nothing outside its record that the key does not say (the
test makes each surrounding otherwise and fails where a row changes under the same key), and a change to how a row is
made raises `LIST_ROW_MAKING` (its digest there says so). What a kept row cannot hold is the list's as it reads it:
what is changing or asked here (`src/views/local.ts`), a message that did not go (`#unsentRow`), a chat opened from another.

## A lock held here

- A lock's chain held (the workspace's `lock` record, a person's pinned chain) is written only through `src/views/lock.ts`
  `hold` (its `chosen`) and `src/personal-lock.ts` `#heard`/`#pin`: what goes on from the head is taken, anything else
  is kept with it and the rules' fork choice decides (`src/lock-keep.ts`). Never put an entry after one whose hash is not
  its `prev`, and never drop one a station showed but past `ASIDE_MOST` (2026-11-12).
- This device signs a lock one entry at a time, in that lock's turn (`Lock.append`, personal-lock.ts `#append`): read
  first outside it, sign after the head held as it begins, give it up once the entry is held, refused or left to the
  cloud. Nothing waits for one turn while holding the other. An entry of its own that lost its place is signed again
  only by the rules of `lock-keep.ts` `againOf`, at most `AGAIN_MOST` times, a person's lock's only with a seed in hand,
  never by asking for one.

## Contracts made from here

- `src/ops.ts` `PARAMS` declares each operation's parameters; `scripts/operations.ts` writes the UIs' bindings from
  it. `src/shapes/schema.ts` declares what every topic gives; `scripts/shapes.ts` writes the clients' types and the
  app's `said` paths. Both are checked in and `--check`ed: change the source and run the script, never edit the output.
- Hermes 0.81 runs it: no `toSorted` and the like, no `Intl` outside `src/hosts/` (names are ordered by the host's
  `collate`). `scripts/hermes-bundle.ts` bundles it; a change that runs only in Node is not done.
- Tests: `pnpm test`, one file `node ../../scripts/native.ts run mesh -- node --test test/<file>.test.ts`; networks
  are simulated on the test's clock (`test/sim-iroh.ts`, seeds in `test/sim-seeds.ts`, `SIM_SEED=` runs one).
