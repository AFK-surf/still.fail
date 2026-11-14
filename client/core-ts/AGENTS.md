# Working on the client core (for agents)

The core is every client's logic: the app on every platform runs it in Hermes (`apps/mbui/engine`, Apple's
`apps/mbui/src/host/apple_core.mm`), the web in a tab's worker (`src/hosts/web.ts`). The UIs send it named calls,
hold subscriptions to its topics and draw what it pushes; they never reach a station or the cloud themselves. Its
design rules (the user, 2026-10-03):

1. **Everything async is Effect**: calls, subscriptions, links, sockets, sync are fibers in scopes (`src/runtime.ts`);
   cancelling is interrupting; timers are the Clock's (a TestClock in tests), never `setTimeout`. `Host`
   (`src/host.ts`, declared in `src/host-of.ts`, made in `src/hosts/`) is what differs per platform, every operation an Effect.
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

## A person's presets and starred models

- They are the person's, carried by their own devices (the user, 2026-11-14): the device keeps its records of each
  workspace (`src/presets-kept.ts`, `presetRecords`; the stars in `choice` `ws:<ws>:liked`), every topic reads those,
  and `src/views/presets.ts` brings each station what it lacks by the one rule (`src/preset-records.ts`, shared with
  the station; never a second copy of it). A change is made here at once and carried as a link opens, as a station
  tells `presets` or `stars`, and as it is made: never on a timer, and a station is brought only what is strictly newer
  than what it said; what one station had newer goes on to the others reached then. A stream that comes back resumed
  is told again the `presets` and `stars` it missed (the station logs them), so it is asked only what the device owes
  that station (`owed`, `owedStars` beside the records: a station passed by while not reached, a carry that failed)
  or where it has never read them of it (`met`, `metStars`: a core updated to this whose stream is restored from the
  cursor its last one kept reads each station once), nothing otherwise (`also`'s `resumed`); a whole read carries as
  a link opens.
- Deletions are kept as a station keeps them, so many of each owner's (`preset-records.ts` `goneKept`, `GONE_KEPT`):
  the device trims what it holds by that rule as it keeps, never bringing one a station would drop (with a bound of
  the workspace's that went round for good, 2026-11-14). A deletion of nobody said (an app from before's, of a preset
  of before not made by who deleted it) is taken only where the device holds that preset as its own, as its own
  deletion one change more (`presets-kept.ts` `ownerless`).
- A station from before (GET /presets/kept answers `no route`) is never PUT to, read and written the old way, and a
  chat on it is opened by the preset's id where it lists it; everywhere else by `presetCopy` of what the device holds.
- People see their own presets; others' only at a press (`otherPresets`, read as shown, kept in memory but for the one
  picked; its `reading` waits for a station `OTHERS_WAIT_MS` at most, so one slow or hung holds the press no longer,
  what it says later joining the list while it is held). Someone else's is looked at, opened with and copied (`preset.copy`), never changed from here.

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
- Where the chain held holds `moved {root}` (2026-11-13; only `handOver` below signs one), what is in force is the rules' state of
  its people's logs and the statements' bodies its stations gave, read with the chain as it moved (`src/lock-moved.ts`,
  rules `state4_moved`, 2026-11-14: what the logs have not said yet of those the chain named, it still says, each such
  device `by` "chain"; kept beside the lock, `lockLogs`
  and `lockBodies`, the person's own log the one personal-lock.ts pins), by this device's clock, each app device by the
  signer its log says (`sign_key`; its key on the log signs that log alone, so this device is on a moved workspace by
  that key on its log, views/pair.ts `movedPlace`): every reader of who and
  what is in the lock reads `src/views/lock.ts` `stateOf`, what reads the chain itself (its own `disable`, its stations
  keeping it, `chosen`, `carry`) reads `fold`. Without the root's log it waits (nobody listed, nothing asked of the
  device); without an `open` there, the chain's settings stand. It is made once and kept in memory while what it is made of stands (`inForceOf`). Nothing is
  signed on a moved chain itself: `Lock.append` answers `lock_moved`, the background writers do nothing, and what was
  pending as the chain moved is told as not taken effect. A change a person asks for there from a device on no log
  of theirs answers `lock_moved` in the words of one not trusted (`core-misc.lock.notSigner`, views/lock.ts
  `notTrustedHere`), and one of another member's app devices says it is theirs alone (`core-misc.lock.othersDevice`);
  `lockMoved`'s English is the background writers' and older paths' alone. `test/lock-moved-state.test.ts` holds it to the model.
  Whether a workspace is in safe mode is `src/views/lock.ts` `safeMode`, by the lock held (kept small beside it,
  `lockSafe`, so a list of every workspace reads a few bytes a workspace); the workspace's view's `locked`
  (the cloud's word, true for good once its chain moved, off or on) only where none is held on (2026-11-14).
- A change of a moved workspace's list is a statement in the person's own log (`src/lock-statements.ts`, views/lock.ts
  `sayMoved`, personal-lock.ts `say`): an entry `ws {t, h}` signed by the device's key on that log, which asks the
  person each time (the owner, 2026-11-13: a phone taken while unlocked, its screen lock not known, then changes no
  list, approves no web page and cannot undo its own removal), its body made as the model's `make` makes one and kept
  here at once. Before the person is asked the rules work out what it would do: whoever it would take out besides is
  said again first (the model's `adopt`: removing someone takes nobody else out, the root AGENTS.md), and one that
  would not do what it means is refused. The body goes only to the stations of its workspace that its list names,
  asked on that workspace's address, never to the cloud nor a station of another workspace (which get the chain);
  taken once one of those took entry and body, else pending, waiting for those. Said so now: a role, a member out, a
  station in (`joinStation`, `addStation` once its code is confirmed) or out, off and on again (the root's person
  alone, on the log that binds them, `lock_root_only`, which names them and the way out, `stillfail lock reset` on a station's machine; the topic
  says it to another owner, `rootText`, and offers the root's person turning it on again while off, `onAgainText`). What lets someone in there (2026-11-13): a web page is `web {id, label, exp}` on its own
  person's log (personal-lock.ts `web`), approved face to face only by a device of that person's on the log that binds
  them (views/pair.ts `movedPlace`), one entry and one ask for every moved workspace it asked in, renewed by a later
  `web`, taken off by `web.remove`; someone's first device is `member {sub, email, lock, role}` said by an owner's or
  admin's device once the code is proved, `lock` the log of their own its hello brought (checked as the credential's
  person's, the asking device on it; `admitOf`), and the removal of an older binding first where their lock was begun
  anew; a person's own new device goes on their log alone. Its role is never the workspace's view's word (the lead,
  2026-11-13: a cloud calling a newcomer an owner would have an owner's device sign them in as one, the ask not showing
  the role): what the person chose as they added them on this same device (views/lock.ts `notedRole`, kept here alone,
  used once, else a member), lowered to the view's where that is lower; one this signer may not give, the note's or the
  view's, shows no code; its prompt says the role approving gives (`roleText`). So someone added as an admin on one device and approved from another comes in a member, and an
  owner makes them an admin by changing their role. Adding a member is the cloud's part alone there (`added`: nothing
  signed, the role noted), and so is changing the role of one not let in yet (`rosterMoved`: the note the new role, an
  owner's only by an owner). A removal said there reads no box key (it calls no views/vault.ts `tookOut`); one of the
  person's own devices taken off their log on this device does, as before a move (views/lock.ts `takeOffBound`,
  vault.ts `tookOutMoved`): a vault left waiting is shown to no device begun anew, so their next device would see none
  of it (2026-11-14). Before taking a device or a member out this device reads the vaults again (`levelVaults`, at most
  its own wait, asking nothing), so a version the one taken out wrote while in is taken while it can be checked; where
  no station could be read, the keying anew that meets another version (`vault_conflict`) reads the station again and
  takes one that checks: on a chain by the chain as it stood, where the chain moved one the device this one just took
  out wrote by the state just before that removal (vault.ts `takeBefore`), the same acceptance as a chain's, no wider
  (the lead, 2026-11-14: a moved workspace does for people what an unmoved one does); one that checks against neither
  is not taken and the vault waits, as on a chain. The vaults
  go by the state in force (vault.ts `lockOf`: `inForceOf`'s `checked`, as a station's do; waiting, one naming nobody):
  a vault keyed for someone a statement, or their own log, took out waits, read by what of the state took its version
  (kept beside the vaults, `vaultTook`, as the vaults held change and as the state is made anew, never as a topic is
  answered; a device begun anew since kept none and shows it not), and is keyed anew by its owner's device as its key
  is next unsealed for something the person does; an item that device writes meanwhile, the key in hand, waits for
  that first (vault.ts `#writable`, 2026-11-14), never refused for its own device's keying. Where this device signs no vault while the state waits, or
  while its log does not say its signer (an entry from before signers were said), the vaults' topic and refusals say so
  (`stateText`, vault.ts `whyNot`), the latter with a press, `confirmText`: `lock.confirmSigner` says it on its log by itself,
  the person asked once (personal-lock.ts `confirmSigner`; else `#restate` says it as another ask comes). A device taken out
  takes what its refusal tells of the removal (views/lock.ts `heardOut`, by the rules as any logs and bodies), and
  `outOf` says who took it out and when (the `lock` topic's `me.outText`, with whom to ask to be added again). A device the stations' state does not name
  is given no log nor body, and told by their refusal that it is left out and whom to ask (views/lock.ts
  `heardLeft`, `leftIn`; station/src/mesh/serve.ts `leftOf`; 2026-11-14): its page is as before a move, not
  confirmed and able to ask, its try dialling those (views/pair.ts `waitingIn`), a hint that lets nobody in; once let
  in it is tried again as the read after its approval finds it refused (`refusedAgain`). Only waiting (no refusal
  says so), it waits as before. A device refused where the chain moved asks that station again at its link's own retry
  (backoff and cap, the link's "a retry after a failure"; views/lock.ts `waiting`): before a move its approval moved the
  chain's head, which the cloud's copy told it; after one nothing it can see changes, and nobody is to open the app or
  press because of a move (the lead, 2026-11-14). Opened again, or the person pressing to ask, it asks at once. A web page whose stations said the list names no app of its person's (their `left.apps`)
  is one nobody can approve there: it asks nobody and says to install an app first (`needsAppIn`, `me.needsAppText`,
  and `lock.pair`'s refusal `lock_needs_app`); one told by a station from before (no `apps`) asks as before.
  `test/lock-left-out.test.ts` runs it on the station's own code. One that lost its
  place is signed again as the model's `resign` does (`again=batch`), only with the seed in hand, never asking for it:
  judged with the others lost with it in the order made by what its body is about (`src/personal-lock.ts` `#how`), the
  same body where its `prev` still stands before it, else one made anew (`src/views/lock.ts` `restated`); meanwhile, and after a restart (what each was for is kept beside the person's lock,
  as `lockAsked` is), told as not in effect. One pending whose act's cloud write then fails is dropped and its bodies
  let go of, as a pending chain entry is (`dropStated`); one taken stays. Its row is on its own workspace's lock topic
  alone. Turning a moved workspace off asks twice (2026-11-13, the lead's: two asks taken over secrets left sealed
  under a lock that is off): the person's own secrets opened first (the box key's ask), then `off` signed (their own
  lock's), the secrets written to the plain library after; one ask for both needs the host to open two sealed values
  under one prompt, not built. `test/lock-statements-made.test.ts` holds the bodies and the take-over to the model.
- What moves a chain is `handOver` (views/lock.ts, src/lock-handover.ts), reached by itself (`movedBySelf`) and by
  tests: the call `lock.handOver` answers `unknown_call` unless chains are handed over by themselves (`handsOver`) or the
  host says `handOverByTests` (the tests' FakeHost, the e2e device's host; never the environment nor a preference). It
  says nothing in anyone's log and asks nobody (the lead, 2026-11-14): the chain as it moved still says what the logs
  have not, so an owner's own app device, by the signer the chain names it with, its person bound there to their log
  pinned here, signs `moved` alone by `Lock.append`'s path once the state as if moved (the rules' of the logs held and
  the chain with that `moved` after it) is the chain's list at its head (`handOverPlan`, its `guard` made again in the
  turn: nobody dropped or added; a bound member's log not held yet holds it back saying nothing, `readBound` reading
  them first), with no key in hand (`movedBySelf`, as the lock is held). Nobody is waited for: a member with no log, with
  only a web page, with an app device on the chain and not on their log, all stay in by the chain. A `moved` that lost
  its place is never signed again (`#lost`): the next `handOver` works it out again. `test/lock-handover.test.ts` runs it
  on the station's own code, `test/lock-handover-model.test.ts` holds its plan to the model's `m8`.
- A chain is handed over by itself (views/lock.ts `handsOver`) on every build from `HAND_OVER_FROM` (src/lock-handover.ts;
  a host made for tests may say `handOverAuto` before it), with no date anyone waits for and nobody told to update (the
  user, 2026-11-14: 无感迁移): each workspace once everything that uses it reads a moved one the same way: every station
  the chain names said in its GET /lock `serves` that it serves `bodies`, `logs`, `builds`, `carried` and `bind` (it reads a
  moved chain as it moved, `stationsWaited`, `keepServes`; never the cloud's word of its version), shown on the owner's
  device (`upgrade`, `upgradeOf`, `waitedLines`: one line a station, the refusal `lock_stations_not_ready` the same); and
  the device that moves it says a build from `MOVED_FROM_BUILD` itself (station/src/api/moved-from.ts; `ownBuild`, as it
  says it to stations; the lead, 2026-11-14: builds between this code's and `MOVED_FROM_BUILD` must move nothing, a
  station of the moved workspace telling them to update at once), said to nobody (`heldBack`; `handOverState`'s `held`).
  No other app device is waited for (the user, 2026-11-14: a phone of his own he no longer used held his workspace
  back, seven days by the rule as it was and nothing on any page saying why: 「用户要是有个设备离线不用了要等 7 天？」):
  one on a build under `MOVED_FROM_BUILD` is told to update by a station of the workspace as it next asks
  (station/src/mesh/serve.ts `movedTooOld`: 请更新, 请刷新页面 on the web) and is in again once it has, nothing approved
  anew. Do not bring a wait for people's devices back. `lock.handOver` answers
  `lock_not_ready` in the upgrade's title). For now, each lifted by its own change: a chain with a web page whose person
  has no app on it (`webOnlyIn`: carried until its `exp`, then nobody can approve it again there, and the page telling
  them to install an app is not drawn yet), and more than `HAND_OVER_MEMBERS_MOST` members bound to a log (`LOGS_MOST` a
  workspace); a host made for tests that calls `lock.handOver` itself is not held to these. The owner's (the user,
  2026-11-14, 「都按推荐」): the person who turned safe mode on (`genesisPerson`) hands over; another owner's device only
  once that person has not in 14 days from the later of `HAND_OVER_FROM` and the genesis, or is no owner on the chain any
  more (`mayHandOver`); after the move only that person turns safe mode off or on again (`lock_root_only`). To people it
  is 安全模式的升级 (the owner, 2026-11-14), never a handover; its `moved` pending is one row, 完成安全模式的升级.
- After the move a person's devices the chain named and their log does not are still put on that log by their other
  device (`ownLocks` reads a moved chain as it moved, `approvedIn`), and an own app device the chain carries is taken
  off by the person's own device in one ask (`lock.removeDevice`, personal-lock.ts `removeCarried`: put on their log under
  a key thrown away, then taken off by it). A member the chain bound to no log, with a log of their own this device is
  on, is bound to it by `bind` (rules/AGENTS.md) riding the next thing they do on their own lock with its one ask
  (views/lock.ts `bindsFor`, personal-lock.ts `#addBinds`; the lead, 2026-11-14: what they did for themselves before the
  move, with nothing more asked and nobody else involved): approving their own device or web page, taking one off, a
  change of the list (`sayMoved` works it out with it, `plan` reading the chain as it moved). One with no log at all
  (apps from before own logs, the common case at a move) has it begun on such an act of theirs on such a device, as
  views/pair.ts `ownLogFor` begins a newcomer's, the `bind` riding it, in that act's one ask (personal-lock.ts
  `seedFor`, views/lock.ts `beginsHere`): approving their own web page, their own new app (which asks them, never
  owners and admins, and brings the key it joins their log with: views/pair.ts `carriedUnbound`), taking a device of
  theirs off. A member the chain named, first
  app device after the move, is admitted face to face as a newcomer is, in the role the state gives them (views/pair.ts
  `admitOf`), what the chain carried of theirs staying.
- After a move the root's person is a member like any other (rules/AGENTS.md, `~root`; the lead, 2026-11-14): another
  owner takes them out with a removal naming the root's log too (lock-statements.ts `cancelsOf`), said only where
  every station the state names said `rootout` (views/lock.ts `rootOutServed`; else the act is refused as before, as
  it would not do what it means), adds them again and approves their new app as anyone's first (views/pair.ts
  `admitOf`); `open` and `off` are said from the log that binds them once it is a real admit (`saysOnOff`). Their
  new app begins its lock anew (personal-lock.ts `begin`: its signer made first and said in the genesis, the chain left
  no lock begun elsewhere to it) and brings the chain pinned to the stations again only for a reason that changed since
  one took it (`#bringPinned`; round 24 of `apps/mbui/e2e/locks-moved.ts`, 2026-11-14: each read and each refusal
  brought it, 878 POSTs in 91 s). `test/lock-left-out.test.ts` counts its asks.
- Known, not built for (the lead, 2026-11-14): a station of another workspace from before build 8799 keeps a stale copy
  of the person's log once they say a statement. A root log holding statements of a half-done handover of builds
  9040–9054 that the chain has since contradicted is held back silently; nothing is built for it.
- Nothing the core does by itself (as a lock comes, a retry, a background writer) reads a value sealed for the
  person's presence or asks them: only what a person asked for on this device does, once for it, and what needs such
  a value otherwise waits until it is in hand for something they do (2026-11-13: `src/views/vault.ts` `rekeyGone` read
  the box key each time the lock came on a device nobody was using; now only where this device took the one out at
  their asking, `tookOut`, else as the vault's key is next unsealed).
- The cloud's taking an entry never counts (2026-11-12): what no station took nor refused by the call's wait
  (ASKED_MS; a background signer's, TAKEN_MS) is pending (`src/lock-pending.ts`), kept on the device beside the lock
  held and never on it, shown on the lock's topic as not in effect, and brought to the stations as one is next read
  (views/lock.ts `deliver`, personal-lock.ts `#deliver`), never on a timer. The cloud is sent an entry once a station
  took it. Whose taking counts are the stations the lock names after the entry (one taken out is brought it behind).
  Only a lock that names no station (the removal of its last station leaves one so; a person's with none left in
  their workspaces), and a person's lock begun anew, are still the cloud's to take; what was pending is brought there
  then (2026-11-13: a lock whose one station retired could never be changed again).

## The base stands apart

The device's mesh (`src/mesh.ts`: its iroh endpoints, the ways to a peer and the choice among them, links, the streams'
framing) and what runs a client (the host, the runtime, errors, words, traces, wakes, the scheduler, the reader of an
event stream, `src/sse.ts`) are the core's
base: another program is built on it without still.fail's business (the owner, 2026-11-14), so a base file imports
only base files and packages, as types too. `scripts/base.ts` holds it: its `BASE` names the files, and the set is
closed: nothing of it reaches, through any number of imports, a file that is not of it (its `STILL` is empty and stays
so). The base says its own words with nothing else loaded (`src/lang.ts`: the two files beside it, `src/lang.zh.json`
and `src/lang.en.json`, the script's `WORDS`: every key a base file says, of no program, the peer "the server"), and
a program gives its own in their place (`words`). still.fail's are its catalog's, where each of those keys is written
as still.fail says it, in a part named by more of the key (`client/i18n/catalog/zh/core-misc.wake.json`): a change to
what still.fail says goes there, and to the base's file only what any program would say. What is still.fail's is given
to it, never imported by it nor named in it: what the core does with the mesh (`src/station/mesh-wire.ts`, its
`MeshEnv` and a `CredentialSource`: a station's requests on its links, the cloud's credentials and the lock's claim,
a lock's refusals, what an app's endpoint takes; its `STATION_MESH`: a station's protocol, what its hello says after
the credential, its peers looked up, the key its stations' addresses are kept under), the catalog, whole, over the
base's own words, and the product's name (`src/i18n.ts`, the one file outside the base that imports `src/lang.ts`: what
says a word imports it, and so does, itself or through what it imports, every file that loads a base file which says
one, so that nothing of still.fail's is run with the base's words: `src/host.ts`, `src/lock.ts` and
`src/hosts/node-iroh.ts` import it for that alone), the UIs' messages and the header that asks a request twice
(`src/host.ts` `Host` and `HEDGE`; the base's
`src/host-of.ts` of them, whose `BaseHost` is all the mesh and the traces ask of a host: `src/mesh.ts`,
`src/trace.ts` and what `src/wake.ts` and `src/error.ts` do for them take that, while `WakingHost` there wraps a
program's whole host, `HostOf`, which is still.fail's, and is its user's choice), its traces' names, what its host is
called where no entry said, and its APIs' paths as a span shows them (`src/route.ts`), where its addon is
(`src/hosts/node-iroh.ts`). A mesh made without `STATION_MESH` (another program's) dials the protocol it names,
says its own hello, looks nothing up and, where it says so, goes through relays alone; what its peer answered the
hello is on the link whole (`Link.admitted`). The script refuses still.fail's name in a base file as well, but where
its `NAMED` lets it be (each text whole, as often as it says), which only falls; `src/lang.ts` imported past
`src/i18n.ts`, however spelt, by a file here, of `apps/mbui/core` or of `web/src`; and any code file git tracks in the
repository (the station's too; TypeScript's and JavaScript's) that loads `src/lang.ts`, or a base file that loads it
(by a static import, an `import("…")` or a `require("…")` of a string), without `src/i18n.ts` among its own static
imports' files, but `test/base-words.test.ts` (its `ALONE`), which holds the base's words alone and then, with the
catalog given, every key of theirs to the catalog's text. So `src/i18n.ts` has run once the load that brought such a
file is over, and a word asked for after that is still.fail's. Not held, so not to be written: a word said as a file
is loaded (its top-level code) where the file reaches `src/i18n.ts` only through a file still being loaded (an import
cycle); a base file loaded by an `import(…)` or `require(…)` of what is no string, or by a name only a bundler or a
tsconfig resolves (but `@core/`, `@stillfail/`); a file git does not track.

## Contracts made from here

- `src/ops.ts` `PARAMS` declares each operation's parameters; `scripts/operations.ts` writes the UIs' bindings from
  it. `src/shapes/schema.ts` declares what every topic gives; `scripts/shapes.ts` writes the clients' types and the
  app's `said` paths. Both are checked in and `--check`ed: change the source and run the script, never edit the output.
- Hermes 0.81 runs it: no `toSorted` and the like, no `Intl` outside `src/hosts/` (names are ordered by the host's
  `collate`). `scripts/hermes-bundle.ts` bundles it; a change that runs only in Node is not done.
- Tests: `pnpm test`, one file `node ../../scripts/native.ts run mesh -- node --test test/<file>.test.ts`; networks
  are simulated on the test's clock (`test/sim-iroh.ts`, seeds in `test/sim-seeds.ts`, `SIM_SEED=` runs one).
