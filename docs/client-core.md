# still.fail client core

The logic of a still.fail client — accounts, still.fail cloud, the mesh links to
stations, requests and live streams, everything read kept on the device — lives
in one TypeScript core, `client/core-ts` (on Effect; docs/core-ts.md for how it
came to replace the Rust core and the rules it is built to), shared by every
client. Only iroh and, on Android, the IO are native:

| Client | Where the core runs | Host (network, storage, time) | iroh |
| --- | --- | --- | --- |
| Web (app.still.fail) | one tab's dedicated Worker (the one holding the Web Lock `stillfail-core`; the other tabs' workers relay to it) | `src/hosts/web.ts`: fetch, WebSocket, IndexedDB (small values), SQLite's WASM build on OPFS | `client/iroh-wasm` (wasm-bindgen, relay only), loaded on the first link |
| The apps (`apps/mbui`: Android, iOS, macOS, Windows, Linux) | Hermes on a thread of its own (`apps/mbui/engine`; on Apple's systems `apps/mbui/src/host/apple_core.mm`), the core as Hermes bytecode | `src/hosts/bridge.ts` over the Rust shell `client/shell` (HTTP, the cloud's WebSocket, files, SQLite, TCP) | in `client/shell` |

The UI never talks to still.fail cloud or a station itself. It sends **calls** and
holds **subscriptions** to the core over one message channel, and renders the
snapshots the core pushes. Several UIs (tabs, windows) share one core: one
device key, one link per station address, one token refresh, one cache.

## Execution model

The core is single-threaded: every piece of work is an Effect fiber in a scope
(`src/runtime.ts`, `Runner`); a call that can be cancelled is a fiber that is
interrupted, a subscription's work ends with its scope. Every timer is on
Effect's Clock (a TestClock in the tests): nothing in the core calls
`setTimeout`. Network waits yield to other work.

It is cache-first: everything still.fail cloud and the stations say is kept in
the signed-in account's SQLite database (`src/data.ts`, `src/db/`,
docs/core-db.md), and a topic is read from it only, by query — subscribing never
asks the network. One sync scheduler
(`src/sync/scheduler.ts`; `src/sync/cloud.ts`, `src/station/sync.ts`) owns all
traffic to still.fail cloud and the stations, keeps everything current by itself
whatever the UI shows, and takes the UI's attention (`client.focus`, a topic
shown) only as priority. A station's requests run two at a time, and two more
of what a UI has open or a person waits on (`URGENT_ROOM`): on a slow link a
read can take a minute, and the chat opened does not wait behind it. Stations
and still.fail cloud push what changes (events, sockets); nothing is read again
on a timer. Every request to a station but a preview's asks its answer
compressed (`accept-encoding: zstd`; an event stream flushed event by event and
compressed against its last megabyte, station/src/mesh/compress.ts), and it is
decompressed as it comes; a station from before sends it as it is. The native
apps' shell takes it apart (libzstd, `zstd.*`: `Host.unzstd`), off the core's
thread: Hermes has no JIT, and fzstd in it made some 10 MB a second of what it
decompresses on an M2 Max, a tenth of V8's (`apps/mbui/scripts/core.sh
zstd-read`), slower again on a phone holding back its clock. The browser,
with no zstd of its own, uses fzstd.
A station's history — every chat's entries (the latest chats first, a page of
each in turn), each listed session's detail where its turns changed and the
latest page of its transcript — is brought onto the device in the background
in batches (`POST /batch`: some 40 reads in one request, compressed as one;
`#history` in sync.ts), behind what is shown: a read a request, a new device
made some 500 of them of one station. A chat opened whose latest entries are
not there yet has that page read alone, at once; a station from before batches
is read a request a read (asked again after an hour).
The exceptions to
keeping everything current: what a station's agents spent (`stationUsage`) and
its archived chats (`archivedRows`) are read only while a page shows them (one
that changed meanwhile is read as a page shows it again).

Topics are keyed collections (`src/collections.ts`): a change to a record
recomputes only the items that read it, and a subscription that says `keyed`
gets per-key insert/update/remove/move ops (docs/core-ts.md, 按 key 的增量).
The mbui app follows those changes the rest of the way: its client
(`apps/mbui/src/core/client.mbt`) applies the ops keeping what they do not touch
(the same object), and sets each subscription's signal (`Sub.changes`, mbui's
`signals`: alien-signals ported) as the core's message for it comes; reading a
topic reads that signal, so what the pages work out of a topic is a computed that
follows it, read again only as it changes, and then item by item: what was made
of an unchanged item is kept (`apps/mbui/src/sfbase/derived.mbt`).

## Host

What differs per platform comes in through one interface, `Host`
(`client/core-ts/src/host.ts`), every operation an Effect:

- `fetch` — one HTTP request to still.fail cloud, whole body; `fetchStream` — a
  streamed response in a scope (tests' stations, the side-by-side run);
  `websocket` — a receive-only WebSocket (still.fail cloud's `/v1/events`) with the
  subprotocols given, open once it resolves, closed with its scope.
- `storageGet` / `storageSet` / `storageDelete` — small persistent values by
  key (accounts and tokens, the device key, UI preferences). Web: IndexedDB
  (`stillfail-core` `values`, as the Rust core kept it); desktop and Android:
  a file per key in the app's data directory, as the Rust core kept them, so an
  update keeps the sign-in.
- `openDb` / `deleteDb` / `memoryDb` — an account's SQLite database (`Sql`:
  `exec`, `run`, `all`, synchronous): desktop node:sqlite, Android the shell's
  (`sql.*`), web SQLite's WASM build on OPFS; `legacyRead` — the former records
  store, read once (docs/core-db.md).
- `nowMs`, `monotonicMs`, `utcOffsetMin` (the viewer's time zone), `randomBytes`,
  `resetConnections`, `tcp` (adbd, native hosts).
- `collate` — names' places in the order people read them in their language (the
  system's collation: numbers by value, case aside, 中文 by pinyin), for a folder's
  files: web and desktop `Intl.Collator`, a native shell `text.collate`; none (or
  a shell from before it), the core orders them by hand. The core itself never
  calls `Intl` (Hermes asks Java for it).
- `emit` — delivers a message to one connected UI (by its client id).

iroh comes from the host too (`src/iroh.ts`): the browser's is relay-only (no
UDP), the native ones are the full endpoint. The credential, renewal, request
lines and the choice of relay are the core's (`src/mesh.ts`). Links are kept by
station address: a station in several workspaces (docs/multi-workspace.md) has
a link in each, dialled to the same station id, each presenting its own
workspace's credential and renewed, dropped and reopened on its own; how fast
a relay brought replies and what went over the links today are the station's,
shared.

## Protocol (UI ↔ core)

Messages are JSON-shaped data (structured clone on the web, JSON strings
natively). Bytes (a file's, a frame's) never go in the JSON as base64: a message carries at most one run of bytes
beside its JSON. A call may carry some, `{ "id": 7, "call": "station.upload.part", "params": { … }, "bytes": <bytes> }`
(a file's part going up); its values and its answer may too, `{ "id": 7, "value": { … }, "bytes": <bytes> }`,
`{ "id": 7, "ok": { "type": "image/png" }, "bytes": <bytes> }` (a file read: its JSON says what they are). On the web
and the desktop they go in the message (structured clone; the desktop's utility process posts `{ json, bytes }` on the
page's port, and the page posts them in its message); Android's engine hands them over as a byte array beside the JSON
both ways (`__native.emitBytes`, `__stillfail.receiveBytes`). On a phone, a 4 MB part made base64, sent as a 5 MB
string and read back took longer than it took to come over the network.

The composer's `composer.add` hands selected files to the core, which owns
their upload and reports progress through the `composer` topic. A new chat's
(`new:<workspace>`) wait (`waits`), kept on the device, and go up as its first
message is taken (`composer.take {station}`), to the station it goes to. On the web,
the worker receives a structured-cloned Blob. A core in Node (the Electron desktop
app's utility process, until 2026-10-26) cannot carry that DOM object: its channel adapter (`src/hosts/file-port.ts`)
keeps the Blob in the page and sends a descriptor, restored to a `FileSource`
before the core reads the call. The core pulls at most one 4 MB part at a time
per upload; the adapter carries those bytes as ArrayBuffers on the same port.
It releases the page's file on success or removal (a new chat's once it leaves
the draft), keeps failed uploads' sources for the outbox's retry, and fails
outstanding reads when the port closes.
Only local file IO lives in this adapter: draft state,
station requests, progress, errors and sending stay in the shared core.
The apps (apps/mbui) do the same through their engine (`src/hosts/bridge.ts`): the app holds
the picked file (Android's `CoreHost.java`) and sends `blob: { hostFile, size, type }`; the
core reads it with `picked.read {file, start, end}` and lets it go with
`picked.release {file}`, calls answered by the app rather than the shell. Its
files go up in a composer of their own (a key no chat has), so a message sent
before they are up names them in `uploads` and waits in the outbox, as the web's
does. `composer.retry {key, id}` sends a failed one up again from what was kept.
A draft read again as the app starts has no picture of its own in the page (the
page drew the ones it picked from their bytes): `composer.picture {key, id}`
answers an image's bytes beside `{ type }` as the device keeps them (one up, as it
went: drive-kept's `sent`; one waiting or going up, as kept for its message:
`outbox`), or null where none is kept (drawn as any other file).

Before its first part a file is named by its content (SHA-256): by the app on a
phone (`picked.hash`, up to 256 MB), else read here when it is at most 64 MB and
the host has `crypto.subtle`. `POST /uploads/parts?…&offset=0&sha256=<hex>` with
no bytes asks the station first: one that keeps that content already (an upload
it took, where a message moved it since, unchanged) copies it and answers the
file, and nothing more goes; otherwise it answers `{ have: 0 }` (as does a
station from before this) and the parts go as before. The station knows what it
was sent since it started, in memory.

UI → core:

```jsonc
{ "id": 7, "call": "job.stop", "params": { … } }          // one answer
{ "id": 8, "subscribe": { "topic": "station.session", "station": "ws1/st1", "key": "…" } }
{ "id": 8, "unsubscribe": true }
{ "id": 7, "cancel": true }                                 // stops a streamed preview, a preview socket, a screen view or a streamed part read: it answers { code: "cancelled" }
```

A call may tell its UI how far it has got before it answers: values under its
id (`{ "id": 7, "value": … }`), then its answer. A UI that goes away cancels its
streamed previews, preview sockets, screen views and streamed part reads
(`station.file.part`, `drive.read` with `stream`: a player's, let go of as it
seeks elsewhere); any other call runs to its end.

core → UI:

```jsonc
{ "id": 7, "ok": { … } }            // or { "id": 7, "error": { "code": "…", "message": "…", "status": 403 } }
{ "id": 8, "value": { … } }         // a subscription's whole current value: its first message, and the first after an error
{ "id": 8, "delta": [ … ] }         // what changed since the previous value
{ "id": 8, "error": { … } }         // the topic could not be read (the subscription stays; a later value clears it)
{ "id": 8, "waiting": true }        // no value yet, and it waits on a station: none of what it shows is on the device
```

`waiting` (store.ts `Source.waits`) is said once, before a first value, of a topic whose value is not on the device:
a chat none of whose messages it opens with are held (station/topics.ts `#opening`). A topic without a value and
without it is the core still reading what the device holds: a page opening waits for it rather than showing what is
to come a moment before what is here (mbui sfapp `page_ready`).

A subscription gets its topic's whole value first, then only what changed:

```jsonc
{ "path": ["detail", "transcript", "timeline"], "append": [ … ] }  // items added at the end of an array
{ "path": ["items", 3, "title"], "set": "…" }                       // a value replaced (path [] = the whole value)
{ "path": ["link", "message"], "remove": true }                     // a key gone from an object
```

Path segments are object keys (strings) and array indexes (numbers). The core
diffs the value it last sent against the current one: objects key by key, an
array that only grew as one `append`, an array of the same length item by
item, anything else as `set`. An equal value sends nothing; ops that would be
larger than the value send the whole `value` instead. `web/src/core/client.ts`
applies the ops, copying only along their paths, and hands the page whole
values. The core sends at most one message per topic per animation frame's
worth of changes (coalesced, ~50 ms); the window is one for all topics, so
what one event changes (a live step ending as the timeline grows) goes out
together, in the order it changed. Live steps are the exception that needs
speed, and they are small.

### Stations and accounts

A station is addressed as `"<workspace>/<station>"`: every station is in a
workspace and reached over a mesh link. `"local"` (a station's own page, gone)
is refused with the error `gone`. The core knows which signed-in account reaches
which workspace (from each account's `/v1/me`) and uses that account's token
for its member credential (30 days, kept on the device: docs/cloud.md).

Workspaces are kept apart (`workspace.ts`): each holds the account that
reaches it, its stations' state, what is waited on for them, the notices of its
chats, what is kept in sync of it and what its new chats were last started on
(`choice` records `ws:<workspace>:station:<id>`, `ws:<workspace>:last`; the
keys from before are read where there is none yet). Nothing of one is read or
dropped through another. What is the device's stays shared (the mesh endpoint,
relays, what is kept on the device, notification settings), and what is an
account's is kept by account. A UI says which workspace it is in (`client.focus {workspace}`);
notices are of every workspace the device has not turned off (`notify.set {workspaces}`), one of a workspace the
viewer is not in with its name before its title (attend.ts).

### Topics

| Topic | Params | Value |
| --- | --- | --- |
| `accounts` | — | signed-in accounts (no tokens) |
| `workspaces` | — | every workspace of every account, with its account and pending invitations |
| `workspace` | `workspace` | the workspace view (members, stations) |
| `link` | `station` | the device's own link to the station: `connecting` (with `last`, how it was last time) / `online` / `reconnecting` / `offline` (not reached: retried with backoff, 2 s doubling to 60 s; every 10 minutes while still.fail cloud says the station is not online or after 12 tries in a row missed, and at once when the cloud says it is back, still.fail cloud's socket opens after a try at it failed (the device's network back), the UI comes back or the station answers a request; streams that end before the station's first keepalive (25 s) wait 2 s doubling to 8 s, cut short by the station answering or the link's pings answering again, as each goes on from where it was (a station tells a stream read afresh where its log is, an id alone); those that would read the whole station again (a station from before that) back off to 60 s, until one holds or the UI comes back; one that was up is tried as coming back for its first 3 misses whatever the cloud says; `reconnecting` too while a stream is open and every way to the station has missed 3 pings in a row (`online` again as one answers or the stream brings anything)) / `error` + message |
| `overview` | `station` | the admin API's `/overview`; its `archiving` with what the core makes of it (present.ts `archiving`): `mode` (`off`, no days; `idle`; `reviewed`), that in a line with Slack's (`summaryText`), and the days each choice offers, the one kept among them (`daysOffered`, `slackDaysOffered`) |
| `sessions` | `station` | `/sessions` (the shown sessions' `SessionSummary`s) |
| `archivedRows` | `station` | `/chats?archived=1`: the station's archived chats. Read only while a page shows it (every chat ever archived: read with each snapshot and archiving, it was a large part of what a slow link carried): again after `chat.archive`, `session.delete` while shown, else marked to be read as it is next shown |
| `threads` | `station` | `/threads`: every thread (`ThreadView`: its sessions, people, first person message, `last` entry, `lastMessage`, the viewer's `read` and `unread`), latest message first |
| `chatRows` | `station` | `/chats`: the viewer's sidebar rows as the station puts them together (`ChatRow`; docs/station-storage.md, The sidebar) |
| `session` | `station`, `key` | `/sessions/:key`: `{ session, threads, turns, jobs }` (no messages, no transcript) |
| `jobs` | `station` | `/jobs`: its background jobs still up (running, or a service being started again), newest first, each with the `chat` it is in as the viewer's sidebar has it |
| `stationUsage` | `station` | `/usage?from=&tz=`: what its agents spent from this device's midnight 29 days ago, days as its clock has them (`rows` added up by day, thread, person, profile and model, each with `cost` at the model's API prices; the `threads`, `people` and `profiles` they name; `since`, the earliest call recorded; `reading` while the transcripts are read for the first time). Read only while a page shows it (some 200 KB, changing with every model call): on its `usage` event (it recorded more; told at most once a minute) while shown, else marked to be read as it is next shown; a station from before it answers 404 |
| `job` | `station`, `id` | `/jobs/:id` as it is now, with what the clients show of it (jobs.ts): kept current by its events, read again each half minute (every 4 s from a station too old to say whose it is) |
| `jobLog` | `station`, `job` (id), `lines` | `{ text, outputAt, last, said }`: the job's last `lines` lines of output and when it last grew (below); `last` its last line, `said` (最后输出 · 3 分钟前) goes out fresh as it changes (jobs.ts) |
| `memory` | `station` | the agents' memory on the station (`StationMemory`, as `memory.get` answers it): read (`GET /memory`) each time it is shown, as agents write it while they work and the stream says nothing of it; what was read last is kept (station/memory.ts) and shows meanwhile, the app opened again too; read again once a skill's sharing changes (`skill.share`). Never read: an error once the station is down or refuses |
| `outflowGrants` | `station` | the programs of the station's machine granted its data (docs/data-outflow.md): `{supported, grants}`, each grant its `id`, `program`, `signed` and `signer` (who signed it as the system said; `signedText` in words), `teamId`, `identifier`, `path`, `said` (what it said of itself), `scopes` (`{id, text}`), `grantedAt`/`grantedText`, `lastReadAt`/`lastReadText` and its latest `reads` (newest first: `at`, `atText`, `scope`, `scopeText`, `rows`). Read (`GET /outflow/grants`) each time it is shown, then as the station tells (`outflow-grants`); kept and shown meanwhile; read again after `outflow.revoke`. A station from before: `supported` false |
| `linkPreview` | `station`, `url` | what a web link in a message is, for its card (`LinkPreview`, as `link.preview` answers it: a page's title, site, icon and picture; a GitHub pull request's or issue's state, author, size, checks), with `time.updatedAt` in words: read (`GET /link-preview`) each time a card shows it (a pull request's state moves; the station keeps what it found a while), what was read last kept (the latest 30, station/memory.ts) and shown meanwhile, the app opened again too. Never read: an error once the station is down or refuses |
| `filePeek` | `station`, `key` (the session whose message names it), `path`, `line?` | what a file a message names by its path is, for its card (`FilePeek`, as `file.peek` answers it: its path, size and when it changed, a few of its lines around `line`, an image's thumbnail, a directory's first entries), with `time.mtime` in words: read (`GET /sessions/:key/peek`) each time a card shows it, what was read last kept (the latest 30) and shown meanwhile, as `linkPreview`. The Markdown tree marks what names a file (`path`, `line`, `shown` on an inline code or a link: paths.ts) |
| `downloads` | — | `{ downloads }`: this device's downloads (`download.start`), newest first, each `{ id, station, key? (a chat's), root?, path?, zip? (a drive's), name, size, loaded, progress (0–1), state (going / waiting / ready / saving / failed), active (not failed: shown as under way, can be called off), statusText, error? }`, told again as one moves on a whole percent; a chat's on its message's card and its preview, a drive's on its row and in the files page's transfers; and `keeping`: what was opened and let go being brought after everything else (src/fill.ts), the one coming first, each `{ id, station, key? (a chat's), root?, path? (a drive's), name, title, size, loaded, progress, state (going, yielding: given way to what is waited on, waiting: its station not reached, queued), statusText, from? }`; a download's and a file's `from` is where it was opened, as what opened it said (KeptFrom: a chat's `thread`, `session`, `file` as its message has it; a drive's `root`, `path`), so the list opens it again there |
| `thread` | `station`, `thread` (id) | `{ first, last, caught, end, entries, thread }`: a window of the thread's entries `first ..= last` (`EntryView`s, never changed once read), holding at most 150 (`WINDOW`) of what its chat shows: its messages, not letters nor edits (counted by entries, a chat mostly of letters showed less than a screen of a whole window, and its two ends took turns dropping each other). It opens where the chat is to be read — the page before the first entry not read and the page from it while something is unread, else where it was left (`chat.place`), else the latest page — and its first value is what is kept of it there, at once: from where it opens or, that not on the device yet (what came while the app was away), from what is held just before it; what is not held joins it as it is read (the station's `threads` say how far each goes). Only with nothing of it kept up to there is it read first. `chat.older` / `chat.newer` bring in the page before / after (a page is kept ahead either way), what shows past those 150 going at the other end; `end`: it reaches the thread's latest entry, so what is said joins it; short of it, what is said waits on the device. `caught`: its last entry read rather than told as it was said. `thread` is its summary |
| `live` | `station`, `key` | the session as it runs (below) |
| `host` | `station` | host samples (`HostInfo`) |
| `net` | `station` | this device's connection to the station, sampled every 2 s while shown and the app is in view (station/topics.ts): its way (`path`, `relay`), round trip, bytes, the last minute's samples, the relays as measured; the last reading kept (station/memory.ts), so it shows as the app opens again, until a connection of its own is open; none before any |
| `way` | `station` | the same reading's way alone, `{ path, relay }`: one sampler with `net`, but it changes only when the way does, so what shows only how a station is reached (the `stations` list) does not go out again with each reading |
| `status` | `workspace?` | what the core is waiting on, when it is worth saying (`StatusView`, status.ts): of a workspace its stations' waits (the relay and links opened for them too), its account's still.fail cloud socket down and the relay opened for no station; with none, all of it, each station said with its workspace's name (`bft · Team`) while the core has more than one workspace |
| `connection` | `station` | what a chat on the station says of its connection (`ConnectionView`, pill.ts): its link down or coming back, else its workspace's `status`; trouble at once, coming back only after 1.5 s, `back` (已连上) 1.5 s only after one was shown. No page shows it any more (the phones dropped the pill over a chat); kept for apps from before |
| `notices` | `workspace?` | what a person hears about while the client runs: chats of theirs that want them (docs/notifications.md); a workspace's, or every one's (each `Notice` names its `workspace` and `station` address) |
| `notify` | `workspace?` | notifications on this device: on or off, asked, whether to hold pushes, the notices to show now (docs/notifications.md), only the workspace's for a page in one |
| `prefs` | — | what this device keeps of how its person likes it (prefs.ts; `prefs.set`) and what it is (`client.device`), with what follows: `keymap`, the keyboard shortcuts (keymap.ts): each action, where it works (`group`, `typing`), its name, the keys that do it here (`keys`: the desktop app's own and those changed on the device in `keys`, else the page's own) and each as a key cap shows it on this device (`labels`, `text`: ⌘⇧H on a Mac, Ctrl+Shift+H elsewhere), `changed`, `listed`; the keys of the workspace menu's places. A client only turns a key press into a binding (modifiers Ctrl, Alt, Shift, Mod in that order, then where the key is: `Shift+Mod+H`; Mod ⌘ on a Mac, Ctrl elsewhere) and looks for it in `keys`; `railView` (`RailView`): the wide screen's rail — every place it can show (`places`: id, words, kind, the chats' list it shows), what can be added to it by kind (`groups`), the `default`, and the rail of a workspace with none of its own (`all`, from `rail`) and each one's own (`by`, from `rails`), each as `{ items, hidden, changed }` (the places this build knows, once each, in the order kept; none kept: the default). A client draws those; only the routes each place goes to and the one lit by a page are its own. The chat a workspace lands on is its `workspaceMarks` entry's `chat` |
| `adbShare` | — | this phone's adb as lent to a station's agents (`AdbShareView`, adb.ts; docs/adb-share.md): whether it is and to which, how the offer goes (`phase`), how the station's adb holds the phone (`adb`, `serial`, `message`), until when, the tunnels open now. Kept in memory only |
| `adbCard` | `station` | a link to the station's 共享调试 as a message shows it (`AdbCard`, adb.ts `card`): 共享调试 and how this phone's adb stands with that station (not shared, shared with another, connecting, the minutes left, what is missing; sent again each minute); `lendable` false on a core that cannot lend it (the web) |
| `joinable` | `workspace` | the stations 添加 station offers to add to the workspace as they are (`JoinableView`, views/memberships.ts; docs/multi-workspace.md): those of the viewer's other workspaces whose home workspace (the cloud does not list them there as `joined`) the viewer is an owner or admin of, not in this one already, each with its address in its home workspace and a line (`甲 · 在线`: online as its link finds it, as the `stations` view says it; still.fail cloud lists no presence); `offered` while the viewer manages another workspace at all, `loading` while one of them is not read. From what is held of the workspaces only |
| `memberships` | `station` | the workspaces the station is in (`MembershipsView`): its `GET /workspaces`, its home one first. Only for the owners and admins of its home workspace (`manages`: the page is in that one, and the viewer manages it); read while a page shows it, kept by its address; again after `station.join`. A station from before several workspaces says so (`error`) |
| `screens` | `station` | the station's screens a person can see and drive (`ScreensView`; docs/remote-screens.md, screens.ts): its `GET /screens` as its stream opens, then its `screens` events; kept with the station's documents (station/memory.ts: what it said last shows as the app opens again, while it is reached anew; none while it is down). Each screen with `line` (what it is, its size, who is on it) and `link` (its page in the app). `control`: the viewer may drive (not a read-only member); `outdated`: a station from before screens (404), which has none until it is updated; `known`: it said which it has since the core started; `note`: why there are none |
| `screenCard` | `station`, `screen` | a link to one of the station's screens as a message shows it (`ScreenCard`, screens.ts `screenCard`): the screen's title and `line` from its list; one the list no longer has (its station reached), `gone`; one of a station not reached, what its id says it is; `peek`: the station previews it (`screen.view` with `peek`, the card showing it live) |
| `filesTabs` | `workspace` | the files' page's tabs on this device (`FilesTabsView`, views/browse.ts: kept among the prefs' `filesTabs`, changed by `files.tabs`): `{ tabs: [{ id, panes, front }], current, front }`, each pane `{ station, root, path }`, `front` the side in front of the tab shown (what the page's address says); null before any |

```jsonc
// live
{
  "loaded": true,             // the stream has sent the transcript it had; until then `timeline` may be partial
  "first": 800,               // where `timeline` starts in the transcript: its latest page first, `history.older` loads those before
  "timeline": [ … ],          // TimelineEntry: the transcript from entry `first`, appended as it grows
  "usage": { "modelCalls": 3, "inputTokens": 1200, "cachedTokens": 900, "outputTokens": 80, "model": "claude-…", "contextTokens": 420, "contextWindow": null, "cost": 0.0123, "unpricedCalls": 0 } | null,
  "steps": [ … ],             // steps in flight (LiveStep; an ended one keeps "ended": true until the entry that records it arrives)
  "phase": { "phase": "requesting", "since": 1790000000000 } | null
}
```

Nothing is read on a timer. Each topic is read once when it starts; after
that only notifications change it:

- `accounts`, `workspaces` and `workspace`: while `workspaces` or any
  `workspace` is live (a view resting on one counts), each signed-in account
  holds still.fail cloud's `/v1/events` socket (subprotocols `ember-events` and
  `ember-token.<access token>`, a token good now asked of the accounts module
  at every (re)connect; auth, events and shapes in `docs/station-storage.md`).
  `{"type":"workspaces"}` reads that account's `/v1/me` again (the
  `workspaces` value), `{"type":"workspace","id"}` that workspace, and
  `{"type":"station","workspace","id","online"}` sets the station's `online`
  (and `last_seen` to now) in the `workspace` value without a request. Every
  time a socket opens, the live account topics are read once (nothing is
  replayed); a socket that cannot open on its first try reads them anyway.
  Sockets reopen with backoff (1 s doubling to a minute, back to 1 s after one
  held a minute) and close when no account topic is live. A change of the
  accounts (sign-in, sign-out) reads the topics again; a token refresh alone
  does not.
- Station topics: while any topic of a station is live, the station's
  `/events` stream is held open, with `?host=1` while a `host` topic is live
  (the stream is opened anew when that changes, and when it is to follow a
  session it does not, one at work or shown; one it follows that no longer
  is stays followed until then; the old one closes once the new one is
  open). Every stream
  after the first asks `since=<the last event id heard>` (an id is the
  station's run and the event's number in it, `<run>.<n>`): one taking over
  from a stream still open, and one coming back after its link went (on a
  weak link that is every minute or so: the link moves to a better way, or
  loses its way). So does the first, when a core before this one heard
  one: the last id is written down in the same write as what its event
  changed (the `heard` record), and an app started again within the hour
  (a phone lets its process go often) reads nothing again either; taken up
  so, the station's history is swept as after reading everything. Not while
  the station is read afresh: a stream not resumed is told nothing of what
  came before it, so the id is forgotten as that reading begins and written
  down again once all of it was read; a core started before then (or after a
  list could not be read) reads the station again. The
  station keeps what it told for an hour (while
  nobody follows too, for one coming back) and tells what came after first,
  with the same ids, then the viewer's sidebar rows and overview as they
  changed meanwhile, and answers `stillfail-resumed: 1`: nothing is read
  again. When it cannot (more than that ago, or another run's), it says
  `missed` and the station is read again, once; a station from before
  resuming does not answer so, and a stream coming back reads it again as
  before (one taking over only on `missed`). Read again, a list some of
  which is held (`chatRows`, `archivedRows`, `threads`, `sessions`; after a
  write too) is asked as what changed of it, `POST /changed/<list>` with
  each held row's digest (`digest.ts`, docs/station-storage.md, Reading):
  only the rows that differ come, and the list is put together from them
  and what is held, in the station's order (an answer that does not add up,
  and a station from before, are read whole; one from before is asked again
  after an hour). Most of a list is as it is held: on a slow link the whole
  lists were most of what reading a station again carried. Events go into the topics
  as they come: `session` replaces the summary in `sessions` (an archived one
  leaves the list) and in its `session` topic (whose `turns` are read again
  only when the summary's `turns` or `lastTurn` differ from them);
  `session-removed` takes it out of `sessions`, out of the threads' sessions
  (a thread left with none goes), and makes its `session` topic a 404 error;
  `thread` appends the new entries to that `thread` topic (those it has are
  skipped; entries past a gap wait while the gap is read, once, with
  `?from=&to=`; history older than what is held is the background's, in
  batches) and, since it does not carry unread counts, reads `/threads/:id`
  for the `threads` and `session` topics that list it (bursts coalesced over
  400 ms; a 404 removes it) — unless the station tells it as the viewer has it,
  `thread-view`, which goes in place and is not read; `thread-removed` takes the thread
  out of them, makes its `thread` topic a 404 error and forgets what is kept of
  it; `read` sets the thread's `read` there, and `unread` to 0 when it covers
  the last entry (else the thread is read again), and turns off `unread` of
  that thread's `chatRows` row when it covers the row's last message; `chat`
  puts a row into `chatRows` (replacing the one with its `id`), `chat-removed`
  takes one out; `job` (a job as `GET /jobs/:id` answers it, whenever it
  starts, starts again, ends or says something) replaces it in its session's
  `jobs` (or goes in front), and in `jobs` while it is up (one not listed there
  yet reads `jobs` again, for its chat; one no longer up leaves); `overview`
  and `host` are the whole values. After the stream
  was down and could not be resumed, every live topic of the station is read
  once when it reopens (`thread` topics only what came after them:
  `?after=<last>`); `link` says how the stream is.
- `thread` shows what is kept on the device of the thread (its latest page)
  at once, then reads `?after=<last>`; with nothing kept it reads the latest
  page. What it reads is kept (docs/station-storage.md, In the client core),
  with the thread's summary and its sidebar title as `threads` and `chatRows`
  have them.
- `live` shows the latest page (200 entries) of the transcript kept on the
  device. A station whose stream answers `stillfail-follows: running` to
  `running=1` follows every session at work itself: it tells each one's steps
  and entries as they are written to every stream whose viewer sees it, and a
  stream that opens is told where each stands (a timeline message with no
  entries) and nothing of before. The device names no session on it, and an
  agent starting its turn or a history shown opens no stream. What the device
  lacks after the lowest entry it holds is read in the background
  (`?after=<last held>`, a hole `?from=&to=&brief=1`) as soon as anything says
  the transcript goes further: that message, a session's summary
  (`transcriptLength`), a read's `end`; a history shown makes that read urgent,
  nothing else. What a session's calls used is the stream's `usage` while it
  works, else its summary's (`usage`, which every session's has, so an agent at
  rest says it with no stream naming it; views/brief.ts `usageNow`): its card
  and its history show that. The history of an agent used lately (its chat or its history
  opened here in the last three days, `Data.usedLately`) is brought whole in the
  background, the page before the lowest entry held after another down to its
  first (`?before=`), as the room on the device allows; another agent's earlier
  pages are not brought until it is used. A station from before is followed on
  `/events?live=<key>&from=<entries it has>&last=200` as before, keeping what
  comes: it sends no more than the last 200 entries, so a timeline message past
  what it has (or before it: the transcript written anew) starts the timeline
  there. `history.older` brings the pages before, from
  what is kept, else `GET /sessions/:key/timeline?before=&limit=`. Both ask
  `brief=1`: what is pushed and paged is what a history shows before a step is
  opened (docs/station-storage.md, Reading); a step or thought in brief says
  so (`brief`, with its `entries`), and `history.detail` reads those entries
  whole as it is opened (`?from=&to=`), never pushed, behind what is shown
  (`Priority.detail`, above `background`, below `shown`). A station from
  before it passes over `brief=1` and sends everything whole.
- `jobLog` reads `GET /jobs/:id/log?lines=<n>` once a run (what was kept of
  it shows meanwhile, station/memory.ts) and follows it on
  `/events?job=<id>&lines=<n>`: the station sends `job-log` (`id`, `lines`,
  `text`, `outputAt`) at once and whenever the log's size or time changes
  (looked at each second while the stream is open). A station that does so
  says `follows: true` in the log it answers; one that does not (older) passes
  over `job=`, and the log is read again instead: after 2 s, doubling while it
  stays the same up to a minute, back to 2 s when it changed.

A topic nobody subscribes to is dropped after a minute.

### Views

The UI does no joining, filtering or grouping of data: every screen subscribes
to one **view** topic that the core has already put together from the
topics above (and keeps current as they change). A view keeps the topics it is
built from subscribed inside the core (`Store::watch`: it counts as a
subscriber and hears each change); a change only marks the view stale, and it
is computed once, when its coalesced emission goes out, however many of them
changed. A workspace view watches the `chatRows` / `link` (for `stations`:
`link` / `overview` / `host` / `way`; for `connects`: `overview`) of the stations that
are online — connected to still.fail cloud right now, as the `workspace` topic says —
and follows the workspace's station list as it changes. It has no value until
the `workspace` topic has one; a failed `workspace` is the view's error, while
a failing station only shows in that station's state. `chat` watches the
station's `threads` and `sessions`, its thread's `thread` (entries),
`overview` and `link` — all asked for at once when it starts, so a chat opens
in one round of requests — and, once `threads` (or the thread as kept) names
them, the `session` of each of its agents. It has a value as soon as its
latest entries are there and its thread is in `threads` — or, before
`threads` is read, as soon as its entries are there from what is kept, with
the thread as kept beside them; its agents fill in after (an agent whose
`session` is not read yet is its summary from `sessions`, without turns or
threads; one that fails is left out). A failed `threads` or `thread` is its
error, and so is its thread missing from `threads` once read (404). Its
`messages` are its entries merged (entries.ts): each message with its latest
edit's text, attachments and quotes (`editedAt`). With `session` instead of
`thread`, `chat` watches that `session`, `sessions`, `chatRows`, `overview`
and `link`.

While a `chats` view is live, a clock waits for the viewer's next local
midnight and recomputes it then (`daysAgo` changes); that is the only timer of
the views.

`scope` is a workspace id.

| View | Params | Value |
| --- | --- | --- |
| `chats` | `scope`, `mine` | the sidebar: `{ me, stations, loading, days }`; every station's rows side by side |
| `stations` | `scope` | every station of the scope, each with its link, overview, host, how this device reaches it (`way`: its words and `via`, from the `way` topic; the figures are `stationNet`'s) and usable models; one the workspace joined (its home is another: docs/multi-workspace.md) says so, `joined`, with its home's name, `home`, when the viewer is in that one too. With `drive?` (true): only those with a drive (their overview says one), `here?` (this machine's station, as the desktop app says it) first, then as the workspace lists them (drive-browse.ts `withDrive`) |
| `stationNet` | `station` | this device's connection to the station with every figure (`StationNet`, present.ts `net`), from its `net`: subscribed where the figures are drawn (station cards, its page), which is what has them sampled; the last kept until a connection of its own is open, null before any |
| `connects` | `scope`, `mine` | every connect of every online station: `{ me, items: [{ station, stationName, connect }], loading }`; with `mine`, those whose `createdBy.id` is me |
| `chat` | `station`, and `thread` (id) or `session` (key) | an item's page: `{ me, thread, title, people, agents, messages, more, outbox, link }`; an agent's or still.fail's message comes with its `md`, its words read as Markdown (client/core-ts/src/markdown.ts: runs of `text`, code with its `ink`), what every client draws: none parses a message itself; `tabs`, its side panel (`ChatTabs`, chat-tabs.ts): of the tabs this device keeps for it (prefs `chatTabs`, by `<station>:<session>`) those it has (an agent's history, a service of one of its agents', `jobs`, `files`, `letters`, a visualization; all while its agents are not known), in their order, and the one `shown` in front (as kept, else the first); none kept, none, but where its agent has no chat yet its history, `auto` (a client where the panel would lie over the chat shows none) |
| `archive` | `scope` | the archive: `{ days, errors, loading, note }`, every online station's archived chats newest first by the day they were archived |
| `chatJobs` | as `chat` | the chat's services and jobs as its pages show them (`ChatJobsView`, jobs.ts): every one, what matters first, each with its dot (`tone`), word, line (`meta`) and times in words (computed again when they next change, to the second); the button's `alarm`, the groups' notes, how many are current and ended, whose ended ones clearing takes |
| `chatLetters` | `station`, `thread` | what the chat's agents and other chats' agents wrote each other (session_send), which the chat's `messages` leave out (`letters` says how many): by the other chat, the one written with last first, each its letters both ways in the order written (`way`), drawn as the chat draws messages. Letters are kept in their own log beside the chat's entries (the station's `GET /threads/:id/letters`, numbered from 1 in it, the thread summary's `lettersLast` how far it goes; channel-kinds.ts `LETTERS`, the device's `letter` table), so a chat's entries, pages and latest page are of what it shows; those from before that log are entries marked `letter`, and the page has both, in the order written. All of its letters and entries are read onto the device for it (`whole` once they are) (`ChatLettersView`, views.ts `lettersByChat`) |
| `chatThings` | `station`, `thread`, `q`? | what was said in the chat besides words (things.ts): its pictures and videos (`media`), other files (`files`), one per message each was sent with; the web links its messages draw (`links`: an agent's as its Markdown links them, code linking nothing; a person's written bare) and the pull requests among them (`pulls`), each once however often said (`count`), at the message it was last said in (`seq`, where 在对话中查看 goes); each kind the latest first, those with every word of `q`; `counts` the chat's whatever `q` is. A pull request says what its card says (title, state, checks, `updatedAt`: the view watches its `linkPreview`). All of the chat is read onto the device for it, as for `chatLetters` (`whole` once it is) (`ChatThingsView`) |
| `imageNear` | as `chat`, and `path` | an image of the chat open in the preview: the ones just before and after it (`ImageNear`, placed.ts), in the order its page shows them (each message's placed files first, then those below it; the outbox's last), each with its `owner`, among all of the chat's held (with a thread: what `chatThings` reads), not only its page's window; told only for the one open, not the chat's every image |
| `usage` | `scope`, `days?` (7, the default, or 30) | what the agents of the scope's online stations spent (`UsageView`, views/usage.ts): `tiles` (cost, calls, input and output tokens), `daily` (each day's cost split by `series`, the four people who spent most and 其他), `lists` (按人 / 按对话 / 按账号 / 按模型, the most spent first, each with its share; a person merged across Slack and the page by email), `notes` (stations offline or too old, the first read under way, models without a price, since when anything is recorded) |
| `longJobs` | `scope` | the services and jobs up longer than an hour on the scope's stations that are up (their `jobs`), oldest first, in groups: `{ groups: [{ key, head, jobs }], lit, ids }`, each job with `whereText` and `age`; `lit` while one is there the rail's bell has not shown (`prefs.jobsSeen`) and the bell is lit by them (`badgeKinds.services`), `ids` what to keep as shown once it opens |
| `driveBrowse` | `owner` (`page`, `tab`), `place` (the client's own name for one place: two sides of the files' page are two), `view` (`columns`, `tree`, `list`), `station`, `root`, `path`, `write?` (names changed and things deleted there) | a folder of a station's drive as a place on this device shows it (`DriveBrowseView`, views/browse.ts; what follows from what, drive-browse.ts; docs/drive.md "Clients"): `arrangement` (the prefs' `driveViews` `sort` and `hidden`), `folders` (each folder shown, by its path, its entries' names in the order shown, hidden ones left out unless asked: the folder; in columns, those before it; in a tree, those open under it; one not read yet is not there), `chosen` (`{ folder, names, anchor?, lead? }`), `open` (the tree's folders open), `widths` (columns dragged, by folder), `keys` (the keys that act now, as `drive.browse`'s `key` names them; the rest are the page's). What is chosen is the place's own, let go with its topic; the trees, the widths and what was last opened in each folder are the owner's, in memory while the core runs. Computed again as a folder it shows is read again and as the prefs change |
| `shareIn` | `scope`, `source`, `query?` | where something another app shares goes (`ShareInView`, share-in.ts; docs/share-in.md): the scope's chats on still.fail's page newest first, the one a thing from the same site went to last first (`kept`, with why), and the stations up now for a new chat (`newOn` the one it starts on) |

`live` (above) stays its own topic: its steps change many times a second,
while `chat` changes with messages.

The `history` view (`station`, `key`; history.ts) is an agent's execution history as every client draws it, put
together from its `live`: each item the transcript entries it draws, what it is (`body`), and on the agent's own work
(its steps and thoughts, and the words it says to itself) `work`, what 只看收发 leaves out.

```jsonc
// chats
{
  "me": { "id": "a@b.c", "email": "a@b.c" },
  "stations": [{ "station": "ws/st", "id": "st", "name": "studio", "state": "online", "message": null }],
  //   state: "online" | "connecting" | "offline" (not connected to still.fail cloud) | "error" (message says why)
  //   error: its rows could not be read, or its link failed; connecting: rows not read yet, or the link
  //   is reconnecting (rows already read stay listed).
  "loading": false,                                // an online station has not answered its rows yet
  "days": [{ "daysAgo": 0, "at": 1790000000000, "items": [{
    "station": "ws/st", "stationName": "studio",   // added here; the rest is the station's row as it is
    "id": "7", "session": "ds:C1:1790000000.000100", "thread": 7, "title": "部署挂了", "agents": [ … ], "last": { … } | null,
    "unread": true, "mine": true, "lastActiveAt": 1790000000000, "connect": "ds" | null, "origin": { … } | null
  }] }]
  // days: most recent first, grouped by the viewer's local calendar day; items by lastActiveAt, newest first.
  // with mine = true only the rows whose `mine` is true.
}
```

The rows are the station's (`GET /chats`, kept current by its `chat` and
`chat-removed` events): which chats and agents are listed, what they are
called, whether they are unread, where their agents came from, and whether the
viewer takes part all come from the station, which knows who is asking. The
core joins nothing here: it puts every station's rows side by side, adds their
station, applies `mine`, and groups them by day.

The `chat` view's `title` is the name people or its agent gave the chat (its
row's, else the thread's `title`, then `autoTitle`). A still.fail chat has none
until then and is `新对话` all along, from the moment it is asked for here: not
the words sent, which come in pieces (here, then the station's chat, then the
message stored in it) and changed the title as each came. A Slack or Feishu
thread is called by the first line of the first thing a person said in it
(`firstText`, Slack mentions left out, spaces collapsed); else its channel
(`#name`), `私信` for a direct message, or `新对话`.

```jsonc
// stations
[{
  "station": "ws/st", "id": "st", "name": "studio",
  "online": true, "lastSeen": 1790000000, "version": "0.4.0",   // from the workspace
  "link": { "state": "online", "message": null },
  "overview": { … } | null,                                      // null while offline or not yet read
  "host": { … } | null,
  "runtimes": [{ "runtime": "claude", "models": ["…"] }]         // claude, codex, dsh, grok, cursor if a profile has models enabled; those models, distinct and sorted
}]

// chat
{
  "me": { … },                   // as in chats
  "thread": { … } | null,        // the ThreadView (with the viewer's `read` position and `unread`, `people`, `last`, `lastMessage`); null before the agent has a chat
  "title": "…",                  // see below (as kept with the entries until `chatRows` is read)
  "people": [ … ],               // the thread's people
  "agents": [{                   // its sessions, in the order they joined
    "session": { … },            // SessionSummary
    "connect": { … } | null,     // the connect that started the session, from the overview
    "profile": { … } | null,     // the profile it runs on, from the overview
    "turns": [ … ],              // TurnRecord, oldest first ([] until its session is read)
    "threads": [ … ]             // ThreadView: every thread it takes part in ([] until read), to name the places in its history
  }],
  "messages": [ … ],             // the thread's messages merged from the entries loaded so far, by seq (a message's entry n)
  "more": true,                  // older entries exist: `chat.older` loads the page before them
  "newer": false,                // newer entries exist (the window is short of the end): `chat.newer` loads the page after, `chat.latest` goes to the end
  "outbox": [{ "id": "out-1", "text": "…", "attachments": [], "quotes": [], "createdAt": 1790000000000, "state": "sending", "error": null, "seq": 42 }],
  //   messages sent from this device that `messages` does not show yet; `seq` (its entry n) once the station has it. An
  //   entry leaves in the same emission that brings the entry with that n (or a later one) into the chat.
  "link": { "state": "online", "message": null }
}
```

Every item of the sidebar opens the same page, the `chat` view: with
`thread`, an internal chat (`surface: "ember"`); with `session`, an agent that
has no chat yet — `thread` null, no people or messages, the agent alone (as
in a chat), titled as the station's item is (the view waits for the station's
`chatRows`); a session that cannot be read is its error. Its chat is made
(`POST /threads {session}`) when the first message is sent, and the page
moves to it. Where the viewer had read up to when a chat opened is
`thread.read` at that moment (from the thread as kept, when the chat opens
from what the device kept); a client keeps it for the visit while reading
moves the position on. The web draws its "以下是新消息" line over the first
message after it that is not the viewer's own and was said before the chat
opened, whether it came from what was kept or from the station after opening.

Grouping by day needs the viewer's time zone: `Host::utc_offset_min(at_ms)`
gives it (web: `-new Date(at).getTimezoneOffset()`).

### Calls

| Call | Params | Result |
| --- | --- | --- |
| `auth.begin` | `redirect_uri`, `return_to`, `device_name` | `{ url }` to open (web: navigate; native: system browser) |
| `auth.password` | `email`, `password`, `device_name` | `{ account }`: signed in with an account still.fail cloud set up for a password (REVIEW_ACCOUNTS: App Store review's); a wrong one fails `login_wrong_password` |
| `auth.complete` | `query` (the callback's query string) | `{ account, return_to }` |
| `auth.signOut` | `account` | — |
| `auth.deleteAccount` | `account` | — : the account deleted in still.fail cloud (`DELETE /v1/me`), then forgotten here as signing out does. Refused `sole_owner` while it is the only owner of a workspace with other members |
| `slack.tokens.edit` | `station`, `form` (the generated `SlackTokenForm`), `input` (changed `appToken`, `botToken`, `connect`, `install`; `clear` invalidates verification) | the transient draft; also published as `{ topic: "slackTokens", station, form }` (`SlackTokensView`) |
| `slack.tokens.verify` | `station`, `form` | `true` only for the current verified draft; errors and identity in the topic. Late results for edited or closed forms cannot advance it |
| `slack.tokens.drop` | `station`, `form` | clears the in-memory draft; disconnecting its owning UI also clears it. Nothing is saved to device storage |
| *an operation* | `station` or `account`, and its own | what the station or still.fail cloud answers; see below |
| `chat.cc` | `station`, `thread`, `to`, `on` | — ; whether what is sent to the chat from here is copied to its Slack or Feishu thread `to` too (the chat view's `cc`; [relay.md](relay.md) "抄送"): none until ticked, held while the core runs. Each `chat.send` meanwhile goes with `cc`, the threads ticked |
| `chat.send` | `station`, `thread`, `text`, `attachments?`, `quotes?`, `client?` (the app it is sent from, for the chat's agent) | `{ seq }`, once the station has it and the chat's `thread` topic (when read) holds it. Only chats on still.fail's page take messages (the station refuses the rest). Meanwhile the message is in the view's `outbox` as `sending` (a failure leaves it there as `failed`, with `error`; one that failed as its station was not reached is sent again, each chat's in order, once the station's link is `online` again: its idempotency key makes it go once) |
| `chat.retry` / `chat.discard` | `station`, `thread`, `id` | sends a failed outbox message again / drops it |
| `decision.answer` | `station`, `thread`, `seq`, `option` (an option's `label`) | as `chat.send`: the viewer's message in the chat, the option's label quoting the post that asked (decisions.ts); refused once the chat's row no longer has that card pending, or for a card that is not an options card |
| `decision.reply` | `station`, `thread`, `seq`, `text` | as `chat.send`: what the viewer wrote in a text card's field, quoting the post that asked (decisions.ts); refused once the chat's row no longer has that card pending, or for a card that is not a text card |
| `chat.tabs.open` / `chat.tabs.close` / `chat.tabs.front` / `chat.tabs.clear` | `chat` (the key its tabs are kept by: `<station>:<session>`, `new:<workspace>` a workspace's new chat), `tab` (not for `clear`), `auto?` (false: from none of those it opens by itself, as a client that shows none of them) | — ; its side panel's tabs changed from what its `chat` view's `tabs` says (chat-tabs.ts), and kept (prefs `chatTabs`): opened, in front (an agent's history after the histories open, before the other tabs; any other last); closed, the one in front, if it was, the last left (one not open: nothing); brought to the front; all closed, the one in front kept. Clients draw `tabs`; what a tab shows and ends (a preview's window) is theirs |
| `keys.set` | `action?`, `keys?` (bindings; none: its own again) | `{ moved, said }`: an action's keys changed on this device (the prefs' `keys`); a binding said in any order of its modifiers is kept as the keymap has it, one that is none (an unknown key or modifier, one twice) or an unknown action is refused `invalid_params`. Each of them is taken from any other action that had it (`moved`, and `said`: what to tell the person, as "⌘K moved here from …"; null when none). No action: every action's own again. `prefs.set {keys}` refuses a binding that is none too |
| `decision.dismiss` | `station`, `thread`, `seq` | `PUT /threads/:thread/dismissed {n}`: the viewer will not take it up; off their rows' line and marks, on every device of theirs (the station keeps it); still pending for everyone else. Off them here at once, back if the station refuses |
| `chat.older` | `station`, `thread` | `{ more }`: loads the page (50 entries) before the chat's oldest loaded entry into its `thread` topic — from what is kept, else from the station — so `messages` grows in front |
| `chat.newer` | `station`, `thread` | `{ more }`: loads the page after the chat's newest loaded entry (it is short of the end), from the device when it is there (kept ahead), as many going at the start; read, not said: nothing comes in with a motion |
| `chat.latest` | `station`, `thread` | — ; the chat's latest page in place of its window (the reader goes to its end); sending from a window short of its end does it too |
| `chat.place` | `station`, `thread`, `seq?` | — ; where the reader leaves the chat: the entry at the top of what shows, short of its end, or none at its end. It opens there next while nothing is unread (held while the core runs) |
| `chat.around` | `station`, `thread`, `seq` | — ; the chat's window about that entry (a message found in it, to be shown): a page before it and one after, read now where not held; left as it is when the entry is well within it |
| `chat.find` | `station`, `thread`, `query`, `bring?` | `{ words, hits: [{ seq, count }], held, of, whole }`: the chat's messages that have every word of `query` (case aside), oldest first, each with how many times the words are in its text; looked for on the device. `whole`: all the chat is on it (`held` of its `of` entries); `bring`: what is not is read first, while its station answers |
| `chat.find.go` | `hits` (`chat.find`'s), `at?` (`{ seq, k }`: the `k`th time in message `seq`), `by` (0 where the reader starts, 1 the next, -1 the one before), `from?`, `to?` (the seqs of the first and last messages showing), `drawn?` (`{ <seq>: n }`: how many times a message's row draws the words, where it is drawn) | `{ at, position, total }`: where the reader goes (core chat-find.ts: starting at what is showing, else the nearest before it, else the first; round from an end to the other, as many times in a message as its row draws), and which of how many times that is (1 the first; 0 none) |
| `chat.relayView` | `connects` (`chat.relayPlaces`'), `query`, `all?`, `bot?` (the connect picked) | `{ link, bot, bots: [{ id, label }], rows: [{ connect, kind, place, name, note, aside }], recent, total, empty, unread }`: what a chat's relay picker shows (core relay-pick.ts): the Slack message's link typed, the bot gone on through (the one picked, else the chat's own, else the first) and the bots among several, that bot's places matching what was typed (those starting with it first), relayed to before first, then by name; nothing typed, of more than 8 only the 5 latest unless `all`; why none (`noPlaces`, `noMatch`), the connects whose places were not read |
| `chat.relayMentions` | `people` (`chat.relayPeople`'), `note` | `{ query, at, rows: [{ id, name, aka?, picture?, note }] }`: whom a relayed chat's note can mention (core relay-pick.ts): what is typed after its last `@` (at its start or after a space, on its last line; null none) and where that `@` is (-1 none), those of `people` whose name or other name has it (those starting with it first, then by name), at most 6, each with the note as it is once they are picked (`@name ` in place of what was typed) |
| `history.older` | `station`, `key` | `{ more }`: loads the page (200 entries) of the session's transcript before its `live` topic's `first` into it — from what is kept, else from the station — so the `history` view's `items` grow in front (`more` in the view: there are older ones) |
| `history.detail` | `station`, `key`, `from`, `to` | — ; reads the session's transcript entries `from` to `to` whole in place of what is kept of them in brief, as a history's step or thought in brief (`brief`, its `entries`) is opened: the `history` view shows it whole once they are in. Behind what is shown (`Priority.detail`); tried while the station seems away too, failing as the request does |
| `history.tool` | `name`, `call`, `result?`, `failed?`, `said?` (a history step's: `said`, its description shows as its name) | `{ call: [ToolPart], result: [ToolPart] | null }`: what the call asked for and what came back, read by what they are (core tool-step.ts): code (`lang?`), facts, a path, diff rows, Markdown (its tree as `md`), a plan, fields, a lead, none, output (`failed?`), JSON; the client draws them in order |
| `chat.read` | `station`, `thread`, `seq` | — ; records that the viewer has read the chat up to entry `seq` (`PUT /threads/:id/read {n}`); nothing is sent when it is read that far already. `unread` in `chats` follows. The clients no longer call it: the core reads a chat up to its newest message while a UI shows its end on a page in front, and up to a message a UI shows whole there (`client.focus` `chat.seen`, attend.ts) |
| `client.focus` | `visible?`, `focused?`, `chat?`, `left?`, `workspace?`, `newChat?` | — ; where this UI's attention is (docs/notifications.md): what is read, a chat's `unreadLine` (held for the visit, older pages loaded first while `unreadAbove`) and which notices show follow from it; `workspace`, the one it is in (else its chat's). What each workspace goes back to (`workspaceMarks` `chat`, the prefs' `openChat`) follows too: the chat a page shows, none once a page shows that workspace's new chat (`newChat`) |
| `station.upload` | `station`, `key`, `name`; the file as the call's bytes | the attachment (into that session's workspace; a message may carry uploads of any session in its chat) |
| `station.upload.part` | `station`, `id` (the UI's, one per file), `name`, `size`, `offset`, `progress?`; the part (at most 16 MB) as the call's bytes | `{ have, file? }` (with `progress`, values `{ sent }`, the part's bytes gone so far, as they go): how much of the file the station has (the next part starts there) and, once whole, the attachment. Up to 1 GB a file; a station from before parts takes it whole once all parts are in, up to 50 MB |
| `station.file` | `station`, `key`, `name`, `thumb?`, `progress?`, `keep?`, `size?` | `{ type }`, the file as its bytes; with `thumb`, the station's small one of an image, kept on the device (`file_kept`, docs/core-db.md): a chat opened again, the app started anew, shows it without reading it again; with `progress`, values `{ loaded, total }` as it comes; with `keep` and the file's `size` as its message says, read a part at a time as `station.file.part` is, each kept on the device with its chat as it comes until let go (client/core-ts src/drive-kept.ts `chat`, as Android keeps the files its viewers open) and answered from there, what came of one let go of before its end kept too and the rest brought after everything else (fill.ts, under `station.file.part`); a file sent up from this device (an image, a video, any) is answered as it went, its thumbnail too, never read back from its station (drive-kept.ts `sent`, kept by composer.ts as it goes up) |
| `station.file.part` | `station`, `key`, `name`, `offset`, `length` (at most 8 MB), `progress?`, `stream?`, `keep?`, `size?` | `{ type, total }`, the part as its bytes (with `progress`, values `{ loaded }`, the part's bytes so far, as it comes; with `stream`, its bytes beside those values instead, 64 KB at a time, for what writes each where it goes as it comes; cancelled, nothing more of it comes over the network, and with `keep` what came is kept): a part of the file and its whole size, for a big one fetched onto the disk a part at a time; `unsupported` from a station before parts; with `keep` and `size`, kept and answered as `station.file`'s, by the ranges read; one sent up from this device answered from it, as `station.file`'s; with `keep`, one a viewer let go of before all of it was kept (a preview closed, a player gone elsewhere) goes on coming by itself (src/fill.ts): a part at a time at the scheduler's lowest priority (`Priority.idle`), only once no request is waited on and none has been for 3 s, stopped (what came kept) as soon as one is, so what a person opens has the link to itself; on as the core starts again (what is kept is its one record), waiting for a station not reached, what was kept let go once the station no longer has the file; a drive's video or song (`drive.read` `played`) the same; not one past 1 GB, nor one whose rest its kind's bound has no room for, nor one a download fetches; `from` (KeptFrom, also on `station.file` and `drive.read`): where it was opened, written down beside what is kept of it; only what says it is brought whole (a still read off a film in its message, saying none, is not), and only what was read in the last 3 days, up to the prefs' `fillMax` (none: 1 GB, 0 any) unless `fillOff` |
| `download.start` | a chat's file: `station`, `key`, `name`, `size` (as the message says); a drive's: `station`, `root`, `path`, `name`, `size`, `mtime` (as its folder lists it); a folder: `station`, `root`, `path`, `name`, `zip: true` | `{ download }`: the file brought onto this device to be saved, by the core in its own scope, a part at a time (4 MB), each part kept as its readers keep it (a chat's `station.file`'s `keep`, a drive's `drive.read`'s `file`), whatever becomes of the page that asked (a preview closed) and of the app (written down until it is saved: one stopped by the app's end goes on as the core starts again, from what was kept); a folder zipped on the station first (`drive.zip`: 正在打包), a drive's file changed since its folder was read fetched as it is now; one whose station is not reached `waiting`, going on once the link is back online; one of that file under way or ready is that one, a failed or waiting one starts again. A station from before parts sends a chat's file whole (up to 50 MB) |
| `download.retry` | `id` | — ; a failed one, or one waiting for its station, tried again now |
| `download.take` | `id` | `{ taken }`: true for the first to take a ready one, which is then `saving`; the app reads it a part at a time (`download.read`) into the system's downloads, then says `download.done` |
| `download.read` | `id`, `offset`, `length` (at most 8 MB) | `{ type, total }`, the bytes: one all here as it is kept (from where it was saved, else the device's kept parts; from the station again only where those are gone, then kept) |
| `download.done` | `id`, `at?` (where the system put the file saved, as the host said it) | — ; saved (or the saving given up): out of the list. Where the host can read the saved file back (`Host.savedRead`: macOS and Windows by its path, Android a Downloads entry of the app's), that file is the device's copy of it: what was kept of it goes, and it is read from there (drive-kept.ts `saved`) until it is found gone or changed, then read and kept as any other again. Elsewhere (the web, iOS: out of reach), what was fetched for it lets go, so the device keeps what it kept before it was asked (a viewer's), not a second copy. One taken and never said done (the app's end) is taken again as the core starts again |
| `download.cancel` | `id` | — ; stopped and out of the list, what was fetched for it let go |
| `fill.stop` | `id` (a `keeping`'s) | — ; no longer brought, what was kept of it let go (its part coming stopped) |
| `fill.stopAll` | — | — ; none of them brought any more, what was kept of each let go |
| `station.poster` | `station`, `key`, `name` | `{ type }` with the JPEG as its bytes, a video's first frame as a small JPEG the station makes, kept on the device as a thumbnail is; null when it has none |
| `file.open` | `station`, `key`, `path`, `offset?`, `length?` | `{ name, path, type, size }`, a file a message names, whole (at most 16 MB), as its bytes (`GET /sessions/:key/open?raw=1`; a station from before `raw` puts them in its JSON as base64, read here); with `offset`/`length` only that part of it, however big it is, `size` its whole size (a station from before parts by path gives the whole, cut here) |
| `code.ink` | `code`, `lang` (as its Markdown block or its file names its language: `ts`, `python`, `json`…) | `{ ink }`: what each piece of the code is (client/core-ts/src/highlight.ts), for code a client holds itself (Markdown it read, a tool step's, a file's); null where it shows as it is (plain text, Markdown, past 256 KB). Worked out here, nothing sent; kept by the code. A client paints each scope in its theme's colours (vitesse light and dark). The core's own Markdown (`Md`) carries the same as its code blocks' `ink` |
| `markdown` | `text` | `{ md }`: Markdown a client holds itself (a file's, a memory's) read as the core reads an agent's message (client/core-ts/src/markdown.ts), its runs of words in `text`; kept by the text. A message's own comes with it (the `chat` view's `md`) |
| `reader.book` | `markdown?`, `text?`, `withText?`, `tree?`; the text (decoded by the client: its bytes are the system's to read) in `text` or as the call's bytes, UTF-8 | `{ id, length, wrapped, joined, chapters: [{ title, offset }], heads, text?, md? }` (`text` with `withText`; `md`, a Markdown book's tree as `markdown` answers it, with `tree`): the text as a reader shows it (client/core-ts/src/reader.ts): line ends made one, a novel hard-wrapped at a column (`wrapped`, 0 none) joined into its paragraphs (`joined`: the text changed, `reader.text` gives it), its chapters (第X章, Chapter N, a title-like line; a Markdown file's headings, levels 1 to 3, as its tree has them), where its heading lines start (`heads`: not indented). The latest three are kept by `id` |
| `reader.text` | `id` | `{ length }`, the kept book's text as joined as its bytes (UTF-8) |
| `reader.search` | `id`, `query`, `limit?` (500) | `{ at }`: where `query` is in the kept book's text (Latin letters without case when found no other way); in a Markdown book, in its words as drawn (not its marks), each where it stands in the text |
| `cache.usage` | — | `{ chats: [{ station, thread, title, sessions, bytes, files }], drive, loose }`: what this device keeps of each chat (its messages, its sessions' transcripts, the thumbnails and posters it showed: `bytes`; the files opened in it, `station.file`'s `keep`: `files`, each `{ key, name, size, bytes, opened }`, the most lately opened first, `bytes` short of `size` while only a part came), the bytes it keeps of the drives' files (`drive.read`'s `keep`, docs/drive.md), and the files kept of no chat known (`loose`, each with its `station`), for a page of what it keeps |
| `cache.clear` | `station`, `thread` | — ; forgets what is kept of the chat (its messages, transcripts, thumbnails and posters, the files opened in it, read again from the station when it is opened); its outbox, draft and row stay |
| `cache.file.clear` | `station`, `key`, `name` | — ; lets go a chat's file kept on the device (`station.file`'s `keep`) |
| `drive.kept.clear` | — | — ; lets go what is kept of the drives' files (read again from their stations when opened) |
| `drive.browse` | `driveBrowse`'s params, `act` and what it takes: `at` (the place shows its folder now: chosen as coming there chooses, what was last opened in it, or as columns carry the choice that opened it), `press` (`folder`, `name`, `mod?`, `shift?`: a click, ⌘ adds or takes one away, ⇧ those between), `choose` (`folder`, `name`: that one alone), `menu` (the same unless it is among those chosen: a right click), `clear`, `key` (`key`, `shift?`: one of the view's `keys`), `type` (`letter`: to the first name starting with what is typed within a second) | `{ acted, chosen, go?, open?, preview?, rename?, remove?, show? }`: what is chosen after it, and what the client does — `go` `{ path, replace }` (another folder shown; `replace`: not a step back in history), an entry opened, previewed, its name changed in place or asked to be deleted (`{ folder, name, dir }`, `remove` a list), a row brought into view and focused (`show` `{ folder, name }`); a tree's folder opened by → and hidden files shown by ⌘⇧. are done in the core. And of the owner's folders, whatever place shows them (`owner`, `station`, `root`, `path`): `opened` (`name`: what was opened in the folder, chosen as it is come back to), `tree` (`folder`, `open?`: a folder of the tree shown at `path` opened or closed), `width` (`width`: the folder's column dragged), `widths` (`owner` alone: every column as wide as the rest again) — null |
| `drive.arrange` | `by?` (`name`, `time`, `size`, `kind`), `down?`, `hidden?` | the arrangement after it: how every place on the device orders a folder's entries and whether hidden ones show, kept among the prefs' `driveViews` (`sort`, `hidden`) |
| `drive.name` | `name`, `station?`, `root?`, `path?`, `taken?`, `beside?`, `dir?` | `{ name }`: the name a new thing takes among the folder's entries as held and the names `taken`: `name` where it is free, else as Finder numbers a new folder (`name 2`…); `beside`: as the station names one kept beside another (`a 2.txt`; `dir`: a folder's name whole) |
| `drive.moves` | `items` (`[{ station, root, abs, name }]`: a station's files dragged), `into` (`{ station, root, path }`), `anywhere?` | `{ moves: [{ root, from, to }] }`: the renames moving them into the folder makes (`drive.rename`'s), each by a root both places are under, else, for a member who browses every folder, by the top of the disk; none for one of another station, one there already or one into itself |
| `files.tabs` | `workspace`, `act`: `arrive` (`pane`: the page's address moved there), `open` (`pane`: a new tab after the one shown), `close` (`id`), `show` (`id`), `split` (`pane?`: the tab shown split, or one again), `front` (`side`), `besides` (`pane`: on the other side of the tab shown) | the tabs after it, as `filesTabs` says them (each pane `{ station, root, path }`); kept among the prefs' `filesTabs` (JSON, by workspace); at most 12 tabs, the last one never closed |
| `files.go` | `workspace`, `typed`, `station`, `abs` (the folder shown) | `{ station, abs, parent, partial }` or null: a folder typed by its path (⌘⇧G) among the workspace's stations with a drive: `mba:~/Projects` names the station before the colon (its name or the start of it), `~` its home, a path without a slash in front is under the folder shown (another station's: under its home); `parent` the folder it is in and `partial` what is typed of its last part (what Tab completes) |
| `station.preview` | `station`, `port`, `method`, `path`, `headers?`, `stream?`; its body, if any, as the call's bytes | a request to a web service on the station's machine (`/preview/<port>`): `{ status, headers }`, the body as its bytes; with `stream`, values `{ head: { status, headers } }` then `{ chunk: true }` with each piece of the body as its bytes as it comes, and the answer (null) at its end. Only waited on (`status`) until its head; cancelled, the station stops asking the service |
| `preview.socket` | `station`, `port`, `path`, `headers?`, `socket` (a name the UI gives it) | a WebSocket of that service, over the mesh only: values `{ open: { protocol } }`, then `{ text }` or `{ binary: true }` (the message as its bytes) for each message; the answer is its close, `{ code, reason }`. Cancelling the call drops it |
| `preview.socket.send` | `socket`, one of `text`, `binary: true` (the message as the call's bytes), `close: [code, reason]` | — ; what the page sends on the socket it named so |
| `screen.view` | `station`, `screen` (its id), `view` (a name the UI gives it), `codecs?` (`["h264","jpeg"]`: those the UI decodes), `maxWidth?`, `maxHeight?` (1920×1080), `quality?` (the 画质 chosen, `smooth`/`hd`/`original`; none for 自动: how high the station lets the bit rate go), `fps?` (the 帧率 chosen, 120/90/60/30/15; none for 自动: the most frames a second the station sends), `control?` (true), `gamut?` (`"p3"`: the UI shows a video tagged Display P3 as such; none: sRGB) | a view of one of the station's screens (docs/remote-screens.md), over the mesh only: values `{ state }` (`ScreenViewState`, whole each time it changes: the phase, 只看/控制, who else is on it, the frame's size, the pointer), `{ config: { codec, width, height, region? } }` with the avcC (H.264) as `bytes` (none for JPEG; `region`: the part of the screen the frames after it show, after a `screen.look`; none, the whole; the state's `width`/`height` stay the whole screen's), then `{ frame: { key, ts } }` with the frame as `bytes` (H.264 in AVCC, or a JPEG); while it drives the screen, `{ clipboard: { type: "text", text } }` or `{ clipboard: { type: "png", size } }` with the PNG as `bytes`, a copy made on the screen; the answer (null) once it ended (the last state says why). The core opens it again when the link drops (`reconnecting`). Cancelling the call ends it |
| `screen.ack` | `view`, `ts` | — ; the UI decoded the frame of that timestamp (the station sends at most 2 ahead of it) |
| `screen.keyframe` | `view` | — ; the UI's decoder lost its state: the next frame is a key frame |
| `screen.input` | `view`, `input` (`{t:"pointer", kind, x, y, buttons}`, `{t:"wheel", x, y, dx, dy}`, `{t:"key", kind, key, code, mods}`, `{t:"text", text}`, `{t:"reveal", path}` (a file dropped into it shown in the machine's file manager, where the state's `drop.reveal` says it can): coordinates 0..1 of the screen, whatever part its frames show) | — ; dropped while the view only looks |
| `screen.clipboard` | `view`, `text` or `png: true` (the PNG as the call's bytes), `paste?` (true) | — ; the screen's clipboard set (text at most 1 MB, a PNG 8 MB), then pasted where its focus is; refused while the view only looks or the screen carries no such type (the state's `clipboard`) |
| `screen.look` | `view`, `region` (`{x, y, w, h}`, 0..1 of the screen: the part the page shows, zoomed in; null, or about all of it: the whole), `width`, `height` (the device pixels it is shown in) | — ; once it has stayed `LOOK_MS` (200 ms: a pinch or a pan asks once, as it settles) the station is asked for that part alone, as large as it is shown (no larger than the view's `maxWidth`×`maxHeight`); asked again of a stream opened again. A station or source that frames no parts goes on with the whole screen |
| `screen.control` | `view`, `control` | — ; 只看 (false) or 控制 (true): the view goes on, opened again with it |
| `screen.bounds` | `view`, `maxWidth`, `maxHeight`, `quality?`, `fps?` | — ; another size for its pictures, 画质 or 帧率 (none: 自动): the view goes on, opened again with them. Opened again for this or `screen.control`, the next stream opens before the one before it closes, so the station has a view of this client's all along (a Windows desktop puts its display's scale and resolution back once its last view ends) and the last frame stays on the page |
| `migrate` | `accounts`, `device` | — (web only: what localStorage held before the core existed) |
| `push.key` / `push.register` / `push.unregister` | see docs/notifications.md | this device's push registration, with every signed-in account |
| `newChat.pick` | `scope`, `station?` (its id), `model?`, `runtime?`, `effort?`, `profile?` (null: the default depth, the station's pick) | — ; what a new chat in the scope starts on, kept on the device (choose.rs): the `newChat` view follows. A model keeps its runtime where it runs there; a runtime changed takes its default depth |
| `newChat.create` | `station` | `{ key, runtime, model, effort? }`: `chat.create` with what is picked on that station; the scope's next new chat starts there. A station down as it is made (its link `offline`) is not asked: the chat waits as failed, and is asked for once the link is `online` again (a chat asked of a station that may have made it is not asked again: it would be made twice). The `newChat` view keeps the station last written to while it is down (`down`), rather than none |
| `newChat.migrate` | `choices` (by station id), `last?`, `lastIn?` | — ; what a client kept before the core did, taken where the core keeps nothing |
| `commands.find` | `query`, `offered` (what the client can do now, in its order: `{ id }` for one the core names — a key's action, `update.page`, `update.app` with `version`, `update.check`, `update.station` with `station?`, `chat.relay` — else `{ id, label, group, words?, typed? }`) | `CommandsFound`: ⌘K's commands (core commands.ts), `{ groups: [{ group, title, commands: [{ id, label }] }] }` in the parts' order (chat, update, global, settings); those whose name, id or other words have `query`, with none typed all but the `typed` ones; the keys' actions only worth a key (⌘K, Esc, back, forward, the chat above or below, the composer, the latest) never. The client draws them and does the one picked by its id |
| `shareIn.open` | `scope`, `source`, `station`, `id?`, `title?`, `key?` (a new chat's composer key, when not `new:<workspace>`) | `{ station, key, session?, thread?, title? }`: what is shared put after what the composer of the chat (`id`, its row) or of the workspace's new chat (to start on `station`) holds, once; nothing is sent, the page opens the chat; the chat is kept as where that site's things go |
| `pick.set` / `pick.save` | `station`, `of` (`new`, `session:<key>`, `connect:<id>`, `connect-new`), and for `set` any of `model`, `runtime`, `effort`, `profile`, `open`, `clear` | a model control's picks until saved (the `pick` topic); `save` makes them what it runs on (`session.settings`, `connect.put`, the new chat's choice), `{ saved }` |
| `pick.repick` | `station`, `of` (`session:<key>`) | beside 自动 in its panel (`PickView.repick`, when another account could run it): the chat's account given back to the station and picked again now, as a new chat's would be (`session.settings` with `repick`; the account drafted gives way, the rest stays drafted), `{ profile, said }`: the account picked and, said, whether it stayed or moved (`said` null from a station that cannot pick again) |
| `pick.borrow` | `station`, `of` | the picked model is one another station of the workspace offers (`ModelOption.availability` `borrowable`): that station shares the profile with this one (`profile.share`, its allow list with this station added; managers only), `{ borrowed }`; the copy comes as any share does (docs/station-share.md) |
| `adb.share` | `station`, `connect?`, `pair?` (adbd's ports, as the app found them), `device`, `android`, `package`, `minutes?` (60) | — ; lends this phone's adb to the station's agents (native cores only), or the offer as it is now; another station's in place of one before (docs/adb-share.md) |
| `adb.stop` | — | — ; lent no longer |
| `adb.pair` | `code` | `{ message }`: the station's adb pairs with the phone through its pairing port |
| `adb.grant` | — | `{ message }`: the station's adb grants the app `WRITE_SECURE_SETTINGS`, to turn Wireless debugging on itself |
| `station.join` | `workspace`, `station` (its address in its home workspace), `name?` (its name there, by default) | `{ joined }`: the station added to `workspace` as it is (docs/multi-workspace.md): an enrollment made there as the account that reaches it, then the station's `POST /workspaces/join {token}` over its home workspace's link; the accounts read again, so it is listed there, and its `memberships`. A refusal is said in words: a station from before (404), a cloud from before (the station says it cannot yet), a workspace lock, the plan's limit |

A UI never makes a request of a station or still.fail cloud itself (no method, no
path): it names what it wants done, and the core knows the request that does it
and what that changes (`ops.ts`; `scripts/check.sh` fails on a UI that asks
for a request). Station operations take `station`: `session.stop`,
`session.warm`, `session.evict`, `session.delete`, `session.settings`,
`session.new`, `chat.archive` (by its thread, else its session; a station from
before archiving threads archives the session; one going in is left out of
`chats` until the station answers, back if it refused), `chat.rename` (by its
thread, else its session), `chats.archived`,
`chat.forSession`, `widget.state`, `widget.setState`, `machineSessions.list`,
`machineSessions.read`, `machineSessions.continue`, `connect.create`,
`connect.put`, `connect.delete`, `connect.reconnect`, `connect.bindSession`,
`connect.putSlackApp`, `slack.verify`, `slack.makeApp`, `slack.dropApp`,
`slack.installed`, `slack.addConfigToken`, `slack.removeConfigToken`,
`slack.people`, `slack.createAppUrl`, `slack.identity`, `profile.add`,
`profile.useMachineLogin`, `profile.put`, `profile.delete`, `profile.quota`,
`profile.check`, `profile.login`, `profile.cancelLogin`, `profile.loginCode`,
`profile.loginBrowser`, `login.new`, `login.code`, `login.drop`, `login.browser` (a sign-in's page opened in the
station's own browser: `{screen}`, docs/remote-login.md), `job.get`, `job.log`, `job.stop`,
`memory.get`, `outflow.revoke` (a program's grant of the station's data, docs/data-outflow.md), `software.update`, `software.check`, `software.channel`, `drive.setRoots` (a station in several workspaces keeps a
list for each: the asker's), `permissions.request` (`grant`: still.fail Helper's window for it up on that Mac, docs/remote-screens.md "Grants"; the overview read again). still.fail cloud's take
`account`: `workspace.create`, `workspace.rename`, `workspace.setRelays`, `workspace.setWay`, `workspace.delete`,
`workspace.invite`, `workspace.addMembers`, `workspace.removeAdded`,
`workspace.revokeInvitation`, `workspace.setRole`, `workspace.removeMember`,
`workspace.enroll`, `workspace.renameStation`, `workspace.removeStation`,
`invitation.preview`, `invitation.accept`, `invitation.decline`,
`loginSession.revoke`, `admin.me`, `admin.createCode`, `admin.revokeCode`,
`admin.setPending`, `admin.removePending`, `admin.feedbackStatus`,
`admin.createWorkspace`, `admin.setLimits`, `admin.enroll`.

An operation answers only after the live topics it touches are current, so
the UI never invalidates caches itself and a page that navigates right after a
write finds what it wrote: an answer that is an overview (profile and connect
edits) becomes the `overview`; a thread (`chat.forSession`, a new chat) goes
into `threads` and the `session` topics; a read position into the threads; a
job stopped into its session's `jobs` and into `jobs` (as its `job` event
would); otherwise the touched topics are read again (sessions → `session`,
`sessions` and `chatRows`, and `archivedRows` while a page shows it; a
session's process stopped or let go (`session.stop`, `session.evict`) → its
`session` alone, the lists that show it its station's `session` and `chat`
events change; warmed (`session.warm`, as a person types) and
`widget.setState` → nothing (its station tells the first, a page reads the
other); a thread answered → `chatRows` as well; connects → `overview` and
`sessions`; profiles, Slack → `overview`; `slack.identity` → `overview` (its
answer) and `chatRows`; a sign-in for a new profile started or given its code
(`login.new`, `login.code`) → the overview's `logins` as the station answered,
while the overview still has it where the call found it: not over what the
station told since). A write to still.fail cloud reads the account topics
again. The station's events bring the same a moment later.

## Layout

```
client/
  core-ts/    the core (TypeScript, Effect): protocol, store, data, sync, accounts, cloud, mesh, station, views
    src/hosts/  web.ts (the worker), node.ts (the desktop's utilityProcess), bridge.ts + hermes.ts (Android's shell)
    src/shapes/ schema.ts: what the core gives its clients, declared once (the clients' types are made from it)
    scripts/    shapes.ts, operations.ts (the clients' types and operation bindings), hermes-bundle.ts
    test/       the core's tests (the Rust core's, ported, and the TS core's own); harness/ the side-by-side run
  iroh-wasm/  iroh alone for the browser (wasm-bindgen), which hosts/web.ts binds
  shell/      Android's native shell (C ABI): HTTP, the cloud's WebSocket, files, SQLite, TCP, iroh
  i18n/       the words (catalog/<lang>/*.json), shared with the station, the web and Android
```

The core's modules (`client/core-ts/src`):

- `host.ts` — the `Host` interface; `runtime.ts` — `Runner`: scopes, fibers, the Clock.
- `protocol.ts` — the messages above.
- `core.ts` — `Core`: accepts client messages, routes calls, manages subscriptions. `core/calls.ts` parses the named calls and validates input; `core/execute.ts` runs them; `core/routing.ts` routes topics; `core/account_state.ts` reconciles accounts, workspaces and their sockets.
- `ops.ts` — station and cloud operations: their requests, their effects on the records, and their contracts (`PARAMS`).
- `store.ts` — topics: values, subscribers, coalesced emission as deltas (`delta.ts`; keyed by `collections.ts`, shaped by `output.ts` and `conform.ts`), eviction.
- `data.ts`, `db/` — the data (docs/core-db.md): a SQLite database per signed-in account (`db/schema.ts` its tables and migrations, `db/account.ts` its writer and reads), the device's own values, what came before imported once (`db/import.ts`).
- `sync/scheduler.ts`, `sync/cloud.ts`, `station/sync.ts` — everything kept current, by itself; `station/topics.ts` — the station topics, read from the records; `station/requests.ts`, `station/wire.ts` — requests over a link.
- `accounts.ts` — sign-in (PKCE), token refresh (one at a time per account), persistence. `cloud.ts` — still.fail cloud's API.
- `mesh.ts` — the device endpoint and station links, one per station address: the credential and its renewal, reopening, hedging on a wake, relay measurement and moving.
- `entries.ts` — a thread's entries merged into messages (edits applied): the one place that does it.
- `workspace.ts` — the workspaces, each with what is its own. `notices.ts`, `attend.ts` (`client.focus`, `notify`), `status.ts`, `pill.ts`, `doing.ts`, `adb.ts`.
- `activity.ts`, `history.ts`, `present.ts`, `format.ts`, `decisions.ts`, `jobs.ts`, `looks.ts`, `changelog.ts` — what the clients show, decided once for every client.
- `refLinks.ts` — still.fail's links as what is written names them (a reference to a chat, the link a chat is given away by, the chat, screen or 共享调试 a link names): read as a message or a draft is drawn, so the web imports it as it is, as it does `markdown.ts`, `mdWords.ts`, `placed.ts`; `refs.ts` keeps a mark's link until it is sent (`chat.ref`).
- `views/` — the view topics (chats, chat, stations, decisions, usage, admin…; `views/memberships.ts`, a station in several workspaces), and `views/local.ts`, the local overlays (outbox, pending chats, renames and pins under way).
- `choose.ts`, `forms.ts` — the new-chat and model pickers, the forms (automatic decisions, Slack tokens, the connect wizard, adding a profile).
- `trace.ts` — traces of user actions (docs/telemetry.md). `testing.ts` — a host for tests.

## Native (the apps)

The apps are mbui's (`apps/mbui`). Each runs the core in Hermes 0.81.4 (React Native's, without React Native) on a
thread of its own: `apps/mbui/engine` (`engine.cpp` behind the C API `engine.h`; Android's `libstillfail_hermes.so`,
Windows' `stillfail_engine.dll`, Linux's `libstillfail_engine.so`), on Apple's systems `apps/mbui/src/host/apple_core.mm`
on Hermes's frameworks. The engine gives the core a task queue, timers and the microtasks drained after each task, and
`__native` calls into the Rust shell (`client/shell`), which does the IO the core asks of its host — HTTP (reqwest,
rustls), the cloud's WebSocket, files per storage key, the accounts' SQLite databases (`databases/`, asked
synchronously), TCP to adbd, iroh — on threads of its own and answers through a C callback. What only the app can do
(`secure.*`, `listen.*`, Android's `picked.*`) goes to the host through the same C API (`src/host/*_core.c`). The core
is bundled for Hermes and compiled to its bytecode by `apps/mbui/scripts/core.sh hermes` (`out/core/core.hbc`, as
`client/core-ts/scripts/hermes-bundle.ts` makes it). A bug that ends a fiber ends the core: every client gets
`{"fatal": "…"}` and the app starts a new one.

Until 2026-10-26 the desktop app was the web app in Electron; the Mac and Windows apps took its place under its ids, so
an installed one's updater moved it over (`scripts/release.sh desktop`, `desktop-win`), and they keep what it kept: the
core's files in its `userData/core`, the sign-in, the keys it sealed (`apps/mbui/src/host/electron_sealed.h`,
`win_electron_sealed.h`). The station it carried and ran is made a service as the new app first starts
(`apps/mbui/src/sfbase/local_station.mbt`). The Android app took the Kotlin one's place the same way (its package, its
key, its files and sign-ins; the Kotlin app stopped at 0.1.4520 and left the repository on 2026-10-29).

## Web

`web/src/core/` is the UI side: it starts the tab's worker, speaks the protocol
over its port, and gives React `useTopic(topic)` (built on
`useSyncExternalStore`) and `call(name, params)`. One tab's worker
(`web/src/core/worker.ts`, the one holding the Web Lock `stillfail-core`) runs
the TS core (`@stillfail/core-ts/web`, aliased to
`client/core-ts/src/hosts/web.ts`) on SQLite's WASM build (loaded by it alone),
and loads `client/iroh-wasm`'s module on its first link; the other tabs' workers
relay to it over a BroadcastChannel and take over when its tab goes (the page
subscribes again on `{rejoin: true}`). `web/src/core/delta.ts` applies deltas (keyed ones
too) for the pages and the desktop's main process alike.

## Operation contracts and module boundaries

The ordinary station and cloud HTTP operations declare what they take beside
their requests, in `ops.ts` (`PARAMS`); `client/core-ts/test/ops-contracts.test.ts`
checks that each reads exactly that. `node client/core-ts/scripts/operations.ts`
generates `web/src/core/operations.ts` from
them; `--check` (CI, `scripts/check.sh`) rejects drift. These
bindings own named calls and parameter packing; the hand-written facades provide
convenient return types and adapters. Special core calls (chat streaming, picks,
local drafts) keep their own adapters. Optional fields distinguish absence (leave
unchanged) from explicit `null` (reset).

The clients' types are made the same way, from `src/shapes/schema.ts` (the
shapes every topic's value passes through on its way out): `node
client/core-ts/scripts/shapes.ts` writes `web/src/core/shapes.ts`, and `--check` keeps them from drifting. A field whose words someone outside the app wrote (a name, a
title, a notice, a command, an error, or a line the core makes with them in it) is marked `said`: the same script lists
where each topic holds them for the mbui app (`apps/mbui/src/sffixture/said_paths.mbt`), whose squeeze sweep makes
them their longest and holds every screen to fit them (docs/ui-panels.md, 放不下的时候).

`connectFlow {station, form}` owns the complete connection wizard. It starts at the
platform where the station has the Feishu connect (its overview lists
`feishuRegistrations`; a station without it starts at Slack's steps). Slack: team,
configuration token, app settings, installation, token verification, model binding
and submission. Feishu (docs/feishu.md): model binding, then the bot made by scanning
(`register`; the registration followed through the overview, its link as a QR code
from `qr.ts`, the connect added by the core itself once the bot is made, the
registration cancelled when the form closes) or an app of one's own verified. Calls
are `connect.flow.open/edit/go/config/make/verify/register/create/drop`.
The core chooses desktop inline versus mobile separate token steps. Each form has
its own `connect-new:<form>` pick and token state, belongs to its client, and is
removed on close/disconnect. Secrets are transient; no draft is written to Data.
Operation generations and token revisions prevent late replies from advancing a
closed or edited form; pending and completed forms cannot submit twice. Nested
pick quota labels use the normal presentation decorator. Web keeps a legacy
wizard only for a desktop host whose bundled core answers `unknown_call`.

Web `action.ts` replaces the station and cloud action implementations. It observes
named calls and shows their `doing` state; synchronous thin wrappers preserve this
metadata through `captureCall`. Android's `CallObserver` carries call metadata in
the coroutine context (isolated across concurrent actions), and `Action` observes
`doing`. Read-only exclusions are generated from `ops.ts` (`QUIET_WRITES` and the reads). Neither
adapter retains token/password/code parameters. A local entry lock prevents a
second click before the core's first update.

Business operations in account/workspace/profile/connection/archive/login and
confirmation controls use that shared state. Local pending flags remain for
browser/OS permissions, sign-in handoffs, image rendering/export, gesture
animations, old core compatibility and host callbacks with no single tracked
operation. Input echoes, optimistic setting queues and displayed errors remain
view concerns; they do not claim whether the station completed a write.
