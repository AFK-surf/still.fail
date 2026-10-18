# Search

One search for everything in a workspace: ⌘K on a computer, the search at the top of the phones' lists, and the agents'
`search` tool. Each station answers for what is on it; the core asks every station of the workspace at once and puts
what they find together with what the device holds. Nothing is gathered in still.fail cloud, and nothing is indexed:
each station looks through its data as it is when asked.

## What is found, and where it comes from

| Kind | What | Found by |
|---|---|---|
| chat | a chat's title (archived ones too), its agents' titles and models | the device (the sidebar's rows) and its station |
| message | every message as it reads now (archived chats' too), the names of its files | the device (what it keeps, `said`) and its station |
| history | an execution history's steps: what the agent said and thought, the calls it made and what they gave. Agents only (`search`): people are not given it | its station |
| job | services and tasks: name, command, folder, port | its station |
| skill, memory | the skills (their files too) and MEMORY.md of the workspace on the station | its station |
| profile | the station's profiles: name, runtime, model, account kind | its station |
| station | the workspace's stations by name | the device |

Later: the files on the station's machine (macOS through Spotlight, Documents/Desktop/Downloads through still.fail
Helper; elsewhere looked through as asked), the cloud's own (feedback), Slack channels' history.

## Station (station/src/search/)

- Nothing is indexed: a thread of the station's own (`search/worker.ts`), on a read-only connection to the store as a
  reader's, looks through the data as it is when asked (`search/sources.ts`): every chat and message (an archived
  chat's from its file), the jobs, the workspace's memory and skills, the profiles; every word must be in a thing's
  title or text, any part of a word, any script, case aside. On ccvm (668 chats, 17k messages) that is about 0.2 s.
- The execution history only when asked for by name (agents' `search`): the sessions most recently active first, each
  one's transcript files looked through as bytes (one put away decompressed as a stream) for every word, ASCII's case
  aside and as JSON writes it; a file that has them all is read and its steps numbered as its history page numbers them,
  its latest steps that have the words found. It stops at the hits asked for, or after 15 s (`left`: the sessions not
  looked through). On ccvm a word found in the latest sessions takes 0.1 s; one found nowhere, every file (2.4 GB, and
  400 MB put away), about 4.5 s.
- The station before kept an index (`search.db`): removed as the station starts.
- `GET /search?q=&kinds=&limit=&offset=` → `{groups: [{kind, hits, more}], building}` (people's, so never `history`;
  `building` always false), as the asker may see: their
  workspace's documents (`ws`; null the home workspace's, `*` every member's), and what only a member who may write
  reaches (`scope: write`) only for them. Those whose title has the first word come first, then the newest.
- Agents: `search` (tools/search.ts) asks every station of the session's workspace (`search.query` over the mesh, as
  `session.read` is), each answering for its own with its chats' links; every kind, the execution history too, when
  none is named.

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
