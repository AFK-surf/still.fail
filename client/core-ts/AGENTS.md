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
   subscription never starts a request. (Exceptions, read only while shown: a station's usage, its archived chats; a
   chat its station's lists do not have, its thread or its session, read as it is opened so that it shows or says it
   is not there, never waits for good.)
5. **An action does not wait for the network**: it takes effect in the core at once (the outbox, a pending chat, the
   overlays of renames, pins, archives, kept in the database across restarts), `doing` tracks it, a failure rolls it
   back and says why. Something made here meets the station's by its exact `clientKey`, never by a guess.
6. **Changes are by key**: a view makes its topic's value again whole as anything it read changes; the store keeps
   what equals the last value as the same objects (`src/collections.ts` `share`), sends a keyed subscriber insert,
   patch, drop and move ops of its keyed lists (`diffKeyed`), and shapes again only items that are not the objects that
   went out (`src/output.ts`). In each of these steps an item that is the object it was costs one comparison of two
   references (or a lookup by the object) and nothing else; the rest is walked only for what is not the same. An item
   a view keeps and hands again is so too where it is not the object the store holds (the store kept the one of
   before, or put one together of both): `share` remembers what a value, a keyed list and each of its items was kept
   as (a topic's own `kept`), so a list a view keeps the items of is a keyed list (`SPECS`). What that still walks for
   one change is counted (`test/view-work.test.ts`).
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
reading growing no faster than what it sends. Those over now are in its `OVER_READ`, `OVER_READ_AGAIN` and `GROWS` (by
what each reads, at its size: a ratio would rise as a fixed part of the reading goes), which only fall; a failure prints
the statements that read most. What the sync writes is held the same way: each cause of `CAUSES`, in turn on one rig
of each setting, from its run to the core at rest, alone (a core started anew, nothing asked) and held (everything the
app asks held), reads at most twice what it writes (text bound to statements that write) and sends, or 8 KB, growing
no faster; `OVER_WRITE` and `GROWS_WRITE` there, which only fall. A new cause is measured by being in `CAUSES`.
What the views, the store and what goes out walk in memory is held the same way (`test/view-work.test.ts`): work.ts
`walked` counts reads tracked, values made again, `share`'s and `equal`'s walks, keyed lists' diffs and the items put
together, copied and fitted as they go out, each to the topic made or sent then, past the items found the same objects
(`same`, one comparison an item of what is shown: printed, not held); each cause, held, walks no more with
what is shown three times as large (the lists' windows, the chat's messages, a `limit`, `lines`, `days`) nor with three
times the chats. Those that do are in its `OVER_SHOWN` and `OVER_CHATS` as pairs (a cause, a counter that grows), which
only fall as a set; by how much one grows is printed, not held (a field more in a row moves what it counts).
What the sync makes of an event of a chat is held on the sync's own path (`test/rows-changed.test.ts`): a station's
rows are made through a memo on its link (`src/station/rows-made.ts` `RowsMemo`: a row whose parts are the objects they
were is the row made before, frozen) and written as the list was last written (`src/db/account.ts` `#chatsHeld`: a row's
object and place, never its JSON), so one change of one chat makes and serialises 1-2 rows and reads no more chats'
JSON than it serialises, the same with three times the chats, and what is stored is what a core started anew makes of
the same records. Of a station that makes its list (`link.shared`, every one since build 7143) a change is by key end to
end: `#remake` names its rows (an id, a thread's, none; whole only for the list or the marks read whole, whose rows
they are, the words), each made alone (rows-made.ts `rowShared`, the viewer's own of the marks kept as sets and maps,
`OwnHeld`) and written by its key at a place of its own (`sharedPlace`, ties by id; a place alone changed, as a list
held in the places of before takes these once, is that row's place written alone, account.ts `#placeChatRow`), so it
looks at no other row: every `glanced` counter stays 0 there but the marks' lists of threads the older path reads
(kept, hidden, muted, suggested, dismissed), walked where a scoped read or what was said puts its own in them, in the
test's `SHARED_MARKS_WALKED` (they go with that path); the older path's (rowsMade) are in its `OLDER_GLANCED`. Both
only fall. `CAUSES` tell a change of one item of a station's list by its key, as the sync takes the station's event
(real-size-asked.ts `listTold`: a chat's row put at its place or dropped, a thread put, a session's summary put), a list
written whole only as the rig is first given it; one told otherwise, as so it would send otherwise, is in its `UNTOLD`.

## The chat table is read by what a view shows

A view never reads a station's chats whole (2026-11-12): every read of the `chat` table is a declaration in
`src/db/chat-reads.ts` (its statement, its bound: one row by a key, the first rows of an order, counts SQLite makes of
columns; the keys it is told by, and those a written row tells, before and after), read through `Data.chatFound` and
`chatCounted`, the records of what it finds taken from the cache by their keys. Its bound holds for the work SQLite does,
not only for what it returns: `test/chat-plans.test.ts` holds every declaration's plan to it (`one`: found by its key
through an index, no walk of a station's rows; `first`: walked in an index's order, so its LIMIT stops the walk;
`count`: of covering indexes alone), on a database as the core opens one (it never runs ANALYZE), and its `OVER_PLAN`
only falls; an index a read needs is made at every open (schema.ts ensureChatColumns). A read is run again only as it
is told (Data keeps each answer by its keys' revisions, #chatRows), and told only by a write that can change it: a
station's read says what of a row its answer reads (`by`: whether the row is in it, its order, what it counts), so an
agent's state changing tells the window nothing, the row reaching the list by its own key (`$chat-row`, the records a
read found by `$chat-record`); `test/chat-told.test.ts` holds every declaration to it (a write that changes an answer
told it, and what a view reads is what the statement gives), and its `TOLD_SAME` (told, the answer the same) only
falls. A read's name is its own. The chat list is a window over the index
(views.ts `#window`), what is overlaid here (local.ts `overlaid`) read apart by its keys. A new read is a declaration
there; `scripts/whole-lists.ts` refuses a whole list read, and its `WHOLE` says where one still is and what takes it away.
A column a read needs is derived as the record is written (SQLite's of its JSON, schema.ts `CHAT_COLUMNS`, held to the
JS's rule by list-rows.test.ts; the core's, `state` and `watched`, Derive: one algorithm each), and for rows an older core wrote (their `made` not `CHAT_MADE`) at the next open: every host opens its
database alone (`locking_mode EXCLUSIVE`), so nothing an older core wrote is read before that.

## What is shared is never written

Unchanged things being the same object is what makes rule 6 work, so a value read from the database
(`Data.shared()`), stored or computed in the store, sent out (`src/output.ts`) or kept in a cache is read-only from
the moment it is made. A function writes only on objects it made this time: copy at the level it changes
(`{ ...m, by: { ...m.by, here: true } }`, `[...a].sort()`), put back what did not change. Tests and the web's
development build deep-freeze shared values (`src/util.ts` `sharedValue`); `scripts/writes.ts` refuses writes on
parameters in the files that make views.

## What is made of a record is kept beside it

What the core makes of one record and of what else its key says is kept beside that record, by one mechanism
(`src/db/kept.ts`, 2026-11-12: the owner's 「从架构设计和测试层面解决」, after it had been written by hand three times):
a declaration in its `KEPT` says the table, the record it is made of, whether it is made as a reader first reads it
(`read`: then at every write of its record, so a write costs by what was shown) or at every write (`written`), and how
it is made (`making`); the views register its maker (Data.makes). Triggers drop a value as its record changes, whoever
writes it; a hit reads no record. `test/kept.test.ts` holds every declaration to that on the workspace of real size, and a
new one is an entry of its `HOW`. So a maker reads nothing outside its record that its key does not say (each
declaration's own test varies its surroundings: list-rows.test.ts, profile-rows.test.ts), and a change to how one is
made raises its `making` (their digests say so). What a kept row cannot hold is the reader's as it reads: a chat list's
what is changing or asked here (`src/views/local.ts`), a message that did not go (`#unsentRow`), a chat opened from
another; the accounts' list's merge across stations and its refills.

## A lock held here

- A lock's chain held (the workspace's `lock` record, a person's pinned chain) is written only through `src/views/lock.ts`
  `hold` (its `chosen`) and `src/personal-lock.ts` `#heard`/`#pin`: what goes on from the head is taken, anything else
  is kept with it and the rules' fork choice decides (`src/lock-keep.ts`). Never put an entry after one whose hash is not
  its `prev`, and never drop one a station showed but past `ASIDE_MOST` (2026-11-12).
- This device signs a lock one entry at a time, in that lock's turn (`Lock.append`, personal-lock.ts `#append`): read
  first outside it, sign after the head held as it begins, give it up once the entry is held, refused or pending.
  Nothing waits for one turn while holding the other. An entry of its own that lost its place is signed again
  only by the rules of `lock-keep.ts` `againOf`, at most `AGAIN_MOST` times, a person's lock's only with a seed in hand,
  never by asking for one; those that lost their place together in the order made, what it signed again of them no
  decision against a later one (`againOf`'s `before`).
  One a person asked for that is then not signed again (someone else decided otherwise since, `AGAIN_MOST`, a refusal)
  is told them as a pending one that failed (`#letBe`), never undone unsaid (2026-11-13).
- Where the chain held holds `moved {root}` (2026-11-13, nothing signs one yet), what is in force is the rules' state of
  its people's logs and the statements' bodies its stations gave (`src/lock-moved.ts`; kept beside the lock, `lockLogs`
  and `lockBodies`, the person's own log the one personal-lock.ts pins), by this device's clock: every reader of who and
  what is in the lock reads `views/lock.ts` `stateOf`, what reads the chain itself (its own `disable`, its stations
  keeping it, `chosen`, `carry`) reads `fold`. Without the root's log or its `open` it waits (nobody listed, nothing
  asked of the device). Nothing is signed on a moved chain: `Lock.append` and `roster`/`enrolled` answer `lock_moved`,
  the background writers do nothing, until the next step makes each a statement. `test/lock-moved-state.test.ts` holds
  it to the model.
- The cloud's taking an entry never counts (2026-11-12): what no station took nor refused by the call's wait
  (ASKED_MS; a background signer's, TAKEN_MS) is pending (`src/lock-pending.ts`), kept on the device beside the lock
  held and never on it, shown on the lock's topic as not in effect, and brought to the stations as one is next read
  (views/lock.ts `deliver`, personal-lock.ts `#deliver`), never on a timer. The cloud is sent an entry once a station
  took it. Whose taking counts are the stations the lock names after the entry (one taken out is brought it behind).
  Only a lock that names no station (the removal of its last station leaves one so; a person's with none left in
  their workspaces), and a person's lock begun anew, are still the cloud's to take; what was pending is brought there
  then (2026-11-13: a lock whose one station retired could never be changed again).

## Contracts made from here

- `src/ops.ts` `PARAMS` declares each operation's parameters; `scripts/operations.ts` writes the UIs' bindings from
  it. `src/shapes/schema.ts` declares what every topic gives; `scripts/shapes.ts` writes the clients' types and the
  app's `said` paths. Both are checked in and `--check`ed: change the source and run the script, never edit the output.
- Hermes 0.81 runs it: no `toSorted` and the like, no `Intl` outside `src/hosts/` (names are ordered by the host's
  `collate`). `scripts/hermes-bundle.ts` bundles it; a change that runs only in Node is not done.
- Tests: `pnpm test`, one file `node ../../scripts/native.ts run mesh -- node --test test/<file>.test.ts`; networks
  are simulated on the test's clock (`test/sim-iroh.ts`, seeds in `test/sim-seeds.ts`, `SIM_SEED=` runs one).
