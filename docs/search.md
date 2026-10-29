# Search

One search for a workspace: ⌘K on a computer, the search at the top of the phones' lists, and the agents' `search`
tool. People find chats, messages, files, services and tasks, stations and members (⌘K its commands and settings'
pages too); agents find those on the stations and the execution histories, skills and memory, profiles besides. Each station answers for what is on it; the core asks every station of the workspace at once and puts
what they find together with what the device holds. Nothing is gathered in still.fail cloud, and nothing is indexed:
each station looks through its data as it is when asked.

## What is found, and where it comes from

| Kind | What | Found by |
|---|---|---|
| chat | a chat's title (archived ones too), its agents' titles and models | the device (the sidebar's rows) and its station |
| message | every message as it reads now (archived chats' too), the names of its files | the device (what it keeps, `said`) and its station |
| job | services and tasks: name, command, folder, port | its station |
| station | the workspace's stations by name | the device |
| member | the workspace's members by name and email | the device |
| file | the machine's files: names, and what text files say | its station: Spotlight on macOS, looked through as asked elsewhere |
| history | an execution history's steps: what the agent said and thought, the calls it made and what they gave. Agents only | its station |
| skill, memory | the skills (their files too) and MEMORY.md of the workspace on the station. Agents only | its station |
| profile | the station's profiles: name, runtime, model, account kind. Agents only | its station |

Later: the cloud's own (feedback), Slack channels' history.

## The machine's files (station/src/search/files.ts)

- macOS: Spotlight asked as a search comes (`mdfind`, at most 3 s): names under the home, what files there say, and the
  apps by name, for a member who may write; a read-only member's only in the folders their workspace pinned. What
  tools make and keep (node_modules, .git, virtual environments, build caches, the home's Library) is passed over;
  names that have the first word first, an app before a file, then the nearer the home's top, the latest. Documents,
  Desktop and Downloads, which macOS keeps from the station, are asked of still.fail Helper (its `files.search`:
  Spotlight as the helper, which holds their grants), only those it is known to hold the grant of: a search never puts
  its window up (a folder not known yet is looked at in the background, found next time).
- Elsewhere: the home (or the folders pinned) walked as a search comes, a folder at a time, nearest the top first, for
  at most 3 s: names of all, the words of text files up to 256 KB; the same folders passed over. What was not reached
  in time is said (`left`).
- How much of the machine a search costs (2026-10-29: a client asked the searches it showed again with each change of
  the station's chats, `mdfind` started more than once a second, Spotlight's `mds_stores` at 790% CPU and 73 hours of
  CPU in 5 days; on a Mac's home a word that common files say, `check`, is in 104k of them, and `*u*` in 198k names,
  17 s): the same words for the same asker are answered as found for 60 s (`KEPT_MS`; past 20 searches a minute,
  what was found up to 10 min before); the machine is searched one search at a time, the others waiting, and one typed
  on (its words grown or shortened from the last of the same asker's) takes the place of the one before, which stops
  (its `mdfind` killed, its walk left); a word shorter than 3 is looked for at the start of names alone, never in what
  files say; what files say is asked for 100 paths at most. A client asks the searches it shows again at most every
  2 s as the station's chats, sessions and jobs change (core `SEARCH_STALE_MS`), not with each.
- Never the station's own (ops/own.ts). The person's own mail, messages, calendars, contacts, notes and photos only
  where the station's owners and admins say so: `PUT /search/settings {personal}` (config.json `search.personal`,
  the overview's `search`), a switch on the station's page.
- A file opens in the drive: a folder entered, a text read, a video or song played, anything else in its folder
  (web/src/searchOpen.ts, Android screens/Search.kt `fileScreen`).

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
- `GET /search?q=&kinds=&limit=&offset=` → `{groups: [{kind, hits, more}], building}` (people's: chat, message, job,
  file only; `building` always false), as the asker may see: their
  workspace's documents (`ws`; null the home workspace's, `*` every member's), and what only a member who may write
  reaches (`scope: write`) only for them. Those whose title has the first word come first, then the newest.
- Agents: `search` (search/tool.ts) asks every station of the session's workspace (`search.query` over the mesh, as
  `session.read` is), each answering for its own with its chats' links; every kind, the execution history too, when
  none is named.

## Core (client/core-ts/src/views/search.ts)

- View `search {scope, query, kind?, limit?}` → `SearchView`: the chats (`items`, as the sidebar's rows; a station's
  archived one drawn as a row of its own, `archived`), the messages (the device's and the stations', each once, newest
  first), the rest by kind (`groups`), what the list still waits on (`wait`) and a line under it (`note`: stations
  offline, too old to search). With `kind`, that kind alone, up to 50. Each thing found besides chats and messages
  says where it opens (`open`, `SearchOpen`: `chat`, `service`, `task`, `station`, `members`, `files` with the
  folder, the place under it and `how`, read or play); each client goes there its own way.
- Call `commands.find {query, offered}` → `CommandsFound`: what ⌘K offers of what a client can do now (core
  commands.ts), by part, those whose name, id or other words have the words.
- Per station `stationSearch {station, q, kind?, limit?}`: asked once the words have stayed as they are for a moment
  (`SEARCH_SETTLE_MS`), while shown, at the urgency of what is shown; held in the link's memory while shown, let go
  after. A station from before search answers 404: said in `note`.

## Clients

- ⌘K (web/src/Switcher.tsx): commands, chats, messages, then each kind under its heading, a few of each; 查看更多
  lists that kind alone, Esc back to all. A service opens its preview (`?service=`), a task the chat's services and
  tasks (`?job=`), a station its page, a member the workspace's settings (`open` as a path: `pathOf`).
- The phones (web/src/mobile/Home.tsx `SearchPage`, Android screens/Search.kt): the same list and the same places.
- A message found, and a chat found by words its title shows late or not at all (`foundText`), is listed by the line
  that has the words (they bold), who said it or where and when beside it, its chat's title under it.

## Finding and reading project skills

The agent's startup skill catalog is local. Before rediscovering a missing project workflow, use
`search {query: "<project or task words>", kinds: ["skill"]}` without `station` to look across the workspace.
Try the project name and task words separately when needed: every word of one query must match.
Skill descriptions should name their actual workflows in the languages people use (for example, offscreen rendering
and 离屏渲染), rather than relying on a single implementation name.

Each skill hit includes a `skill_read {station, name}` call using the station id and exact skill name. This reads
`SKILL.md` in full and lists the skill's adjacent Markdown references; pass `file` to read one of those by its listed
name. It does not install, share, edit or execute the skill. Other assets and nested references still use the station's
file/task workflow. An older station without `skill.read` reports an error; the search itself continues to work.

`skill.read` travels over the authenticated workspace mesh. The destination selects its catalog from the workspace
identified by the transport, never a caller-supplied filesystem path. Local reads use the session's workspace. Only
skills and Markdown references already present in that catalog can be read; another workspace's catalog is not a
fallback. Station names must be unique for reading; search supplies the id to avoid ambiguity.
