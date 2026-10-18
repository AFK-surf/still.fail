# Search

One search for everything in a workspace: ⌘K on a computer, the search at the top of the phones' lists, and the agents'
`search` tool. Each station answers for what is on it; the core asks every station of the workspace at once and puts
what they find together with what the device holds. Nothing is gathered in still.fail cloud.

## What is found, and where it comes from

| Kind | What | Found by |
|---|---|---|
| chat | a chat's title (archived ones too), its agents' titles and models | the device (the sidebar's rows) and its station |
| message | every message as it reads now (archived chats' too), the names of its files | the device (what it keeps, `said`) and its station |
| history | an execution history's steps: what the agent said and thought, the calls it made (as a history names them), the start of what they gave | its station |
| job | services and tasks: name, command, folder, port | its station |
| skill, memory | the skills (their files too) and MEMORY.md of the workspace on the station | its station |
| profile | the station's profiles: name, runtime, model, account kind | its station |
| station | the workspace's stations by name | the device |
| file | the machine's files: names, and what text files say | its station: Spotlight on macOS, its own index elsewhere |

Later: Documents, Desktop and Downloads on macOS through still.fail Helper, the cloud's own (feedback), Slack
channels' history.

## The machine's files (station/src/search/files.ts)

- macOS: Spotlight asked as a search comes (`mdfind`, at most 3 s, never copied into `search.db`): names under the home,
  what files there say, and the apps by name, for a member who may write; a read-only member's only in the folders
  their workspace pinned. What tools make and keep (node_modules, .git, virtual environments, build caches, the home's
  Library) is passed over; names that have the first word first, an app before a file, then the nearer the home's
  top, the latest. Documents, Desktop and Downloads are kept from the station by macOS: not found yet.
- Elsewhere: the home and the folders pinned walked into `search.db` every six hours by the index's thread (names of
  all, the words of text files up to 256 KB; the same folders passed over), for the same people.
- Never the station's own (ops/own.ts). The person's own mail, messages, calendars, contacts, notes and photos only
  where the station's owners and admins say so: `PUT /search/settings {personal}` (config.json `search.personal`,
  the overview's `search`), a switch on the station's page.
- A file opens in the drive: a folder entered, a text read, a video or song played, anything else in its folder
  (web/src/searchOpen.ts, Android screens/Search.kt `fileScreen`).

## Station (station/src/search/)

- `search.db` beside `stillfail.db`: a database of its own, made where missing, so it is dropped and built again at
  will and no version of the station's data depends on it. One table of documents (`docs`: kind, workspace, scope,
  title, body, time, what opens it) with an FTS5 index over title and body (`tokenize='trigram'`: any part of any word,
  any script, case aside). A term of fewer than three characters (most Chinese words) has no trigram and is looked for
  in the text itself (`instr`).
- Each document belongs to a source (a thread, a session's transcript, a session's jobs, a workspace's memory, the
  profiles), indexed as a whole and marked with the version indexed (`marks`): a thread from the last entry indexed
  (what was said since, and what an edit changed), an archived one whole once its file changes; a transcript from the
  last step indexed while its files only grow.
- The index is kept by a thread of its own (`search/worker.ts`), on a read-only connection to the store as a reader's:
  told what changed by the store's changes (`search/search.ts`), and every ten minutes, and at start, it looks over
  everything for what it was not told (memory an agent wrote, a start after the station was away). It answers what is
  asked between sources.
- `GET /search?q=&kinds=&limit=&offset=` → `{groups: [{kind, hits, more}], building}`, as the asker may see: their
  workspace's documents (`ws`; null the home workspace's, `*` every member's), and what only a member who may write
  reaches (`scope: write`) only for them. Those whose title has the first word come first, then the newest.
  `building` while the first look over everything since the start is not done.
- Agents: `search` (tools/search.ts) asks every station of the session's workspace (`search.query` over the mesh, as
  `session.read` is), each answering for its own with its chats' links.

## Core (client/core-ts/src/views/search.ts)

- View `search {scope, query, kind?, limit?}` → `SearchView`: the chats (`items`, as the sidebar's rows; a station's
  archived one drawn as a row of its own, `archived`), the messages (the device's and the stations', each once, newest
  first), the rest by kind (`groups`), what the list still waits on (`wait`) and a line under it (`note`: stations
  offline, too old to search, still indexing). With `kind`, that kind alone, up to 50.
- Per station `stationSearch {station, q, kind?, limit?}`: asked once the words have stayed as they are for a moment
  (`SEARCH_SETTLE_MS`), while shown, at the urgency of what is shown; held in the link's memory while shown, let go
  after. A station from before search answers 404: said in `note`.

## Clients

- ⌘K (web/src/Switcher.tsx): commands, chats, messages, then each kind under its heading, a few of each; 查看更多
  lists that kind alone, Esc back to all. A step of a history opens its chat's history at it
  (`?history=<session>&entry=<n>`), a service its preview (`?service=`), a task the chat's services and tasks
  (`?job=`), a skill or memory the station's memory page, a profile the profiles, a station its page.
- The phones (web/src/mobile/Home.tsx `SearchPage`, Android screens/Search.kt): the same list and the same places.
