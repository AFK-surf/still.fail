# A station's drive

A station shows its members the files of its machine: they browse them, read
and play what is in them, upload, rename and remove, and put them into a chat's
message. It is zdrive (`zzj3720/zdrive`) brought into still.fail: zdrive's ops
and path sandbox, over the members' link the station already has (no pairing,
no allowlist of its own, no transport of its own).

## Who may do what

- **Members who may write** reach every folder of the machine (`anywhere`):
  whoever can have an agent run there could have it read any file anyway, so
  the drive does not pretend otherwise. They start at the machine's home; any
  absolute path is a root to ask from.
- **Configured roots** (`drive.roots` in config.json) are retained for older
  integrations. Existing roots appear among a person's favorites, where they
  can be removed without changing the station. still.fail workspace members
  can browse every folder; an older integration may instead give the station a
  read-only viewer, which can only browse and read configured roots.
- Every path is relative to a root and stays in it: `..` is refused; for a
  viewer, a link that leads out of the pinned folder is refused (and not
  listed). The station's own data (its data directory, config, the profiles'
  homes, the machine's runtime logins) is never reachable, as for the device
  tools.
- On macOS a station launchd runs may not open Documents, Desktop, Downloads or
  disks (removable, network): the drive reaches them through still.fail Helper,
  which holds the grants (below).

## Folders macOS protects (drive/fs.ts, helper/files.ts)

macOS's privacy protection keeps the home's Documents, Desktop and Downloads,
and the disks mounted in /Volumes (not the system's own), from a process nobody
gave access to; a station launchd runs is such a process, and macOS never asks
about it. The drive takes them through still.fail Helper (the station's macOS
app, docs/remote-screens.md, native/helper's Files.swift), which macOS asks
about and which holds the grants, so they open without the station restarting:

- Per path, on macOS with the helper: one at or under such a folder (by its
  name) goes through the helper; everything else, and every other system, is
  read directly, as before. The station does not touch those folders itself,
  not even to see whether it may: macOS can hold such a call on a prompt for
  the station's launcher that nobody answers (macOS 27 on studio, 2026-10-17:
  the station's main thread stayed in `opendir` on ~/Documents until killed).
  The station checks the path first as it does any (its root, `..`, links out
  for a viewer, its own data); the helper is told the root it may reach and
  what it may not, and refuses anything else.
- The helper's `files.*` requests (main.swift, Files.swift) list, stat, read a
  range, write, make a folder, rename, remove, put in the trash (macOS's own,
  as Finder does: the home's, a disk's); a file's bytes go over the
  helper's socket as they are read or written (a read of 8 MB at most, an
  upload's part, a file copied for a chat), never a whole file in memory there.
- The grants are Files and Folders, one per folder (Documents, Desktop,
  Downloads, Removable Volumes, Network Volumes): macOS grants them only through
  its own prompt, when the app opens the folder, and they take effect at once
  (no restart). Full Disk Access (System Settings, dragged in) covers them all
  as well. The helper looks before it touches anything (`TCCAccessPreflight`:
  granted, denied, never asked) and never opens a folder it has no grant for: a
  prompt nobody answers would hold the call.
- Without the grant, a request for such a folder is refused (`permission`, its
  words saying so) and the helper's window comes up on that Mac with a row for
  that folder, once: not again (nor brought forward) while it is up, nor for
  three minutes after it was shown, so a page read again, a client retrying or
  a refresh never puts it up again; the refusal says the window was just closed
  then. It is the station's one window for grants (helper/grants.ts): one asked
  for by an agent counts the same; a person's own ask from the station's page
  puts it up again however lately it was shown. Its Allow has the
  helper open the folder, and macOS asks. One refused before opens System
  Settings › Files and Folders instead, where the helper has a switch for it.
  The window tells the station when a grant changes, and the roots are told
  again (`unreadable` becomes `ok`). A pinned root in such a folder is
  `unreadable` until the helper has the grant.
- Agents are not affected: their commands still run under the station's
  launcher, which macOS keeps out of these folders as before, or prompts for
  them (that prompt holds the agent's own process, not the station).

## Directories and files the station is given (ops/places.ts)

Besides the drive, people and agents name folders and files for the station to
use: a chat continued from a terminal session runs in that session's directory,
`job_start` takes a `cwd`, `station_task` a `dir` it syncs, `chat_post`,
`session_send` and `chat_create` take `files` (and a still.fail chat's local
links become attachments). On macOS the station never looks at one in a
protected folder on its own thread (the same classification as the drive,
`protectedPlace`, plus iCloud Drive's ~/Library/Mobile Documents and the file
providers' ~/Library/CloudStorage, which macOS protects too but still.fail
Helper has no grant for):

- The path is walked link by link with lstat, never stepping into such a
  folder; outside them it is looked at as before. In one (by its name or
  through a link), still.fail Helper is asked (`files.stat`; an attachment is
  copied into the session's uploads with `files.read`); without a helper for
  it, a child process looks (or copies), killed after 5 seconds, so a prompt
  macOS shows holds that process, not the station, and the request is refused
  saying the folder may be asking for permission on that Mac.
- A grant the helper lacks is refused naming the folder
  (`station.place.grant`) and puts the helper's window up for it, as the drive
  does (once while it is up and for three minutes after, whoever asks); an
  agent is told to call `permissions` with that grant and post its answer with
  need_human.
- `station_task`'s `dir` is read by the station itself as it syncs, so the
  helper's grant is no use there: only the station's own access counts, looked
  at by the child process.
- The pages' previews of a file a message names (`/sessions/:key/peek`) do not
  reach into these folders (`station.files.protected`); the drive opens them.
  The overview's pinned roots in them say what the helper's grant is known to
  be, never listed by the station.
- Left as they were: without still.fail Helper the drive itself still reads
  these folders directly; `secret_run`'s `cwd` is only where its command runs
  (nothing looked at); the device tools (off by default) read what they are
  asked directly; a mount point in /Volumes is looked at itself (lstat) to tell
  the system's own disk.
- Once the helper has the grant the station goes on (an agent starts in such a
  directory); the agent's commands then run as the launcher does (above).

## Station (station/src/drive/drive.ts, api/routes/drive.ts)

| Request | Answer |
|---|---|
| `GET /drive` | `{roots: [{path, name, state}], manage, write, anywhere?, home?, trash?, watch, zip?, transfers?}` (also in the overview as `drive`; `state` `unreadable` for a folder macOS protects until still.fail Helper has its grant) |
| `PUT /drive/roots {roots}` | the folders pinned, by any member who may write; each new one must be there, a folder, none of the station's data |
| `GET /drive/folders?path=` | members who may write: the folders in `path` (the home when empty), to pick one to pin; with the way there (`crumbs`, from the home or the top of its disk) and the places to start from (`places`: the home's folders, then the disks: macOS's in /Volumes, Linux's in /media/<user> and /mnt, Windows' drives `C:\` to `Z:\`). Each folder says whether the station may list it (`unreadable`), looked at off the station's thread; one macOS protects (a disk mounted anywhere, OrbStack's NFS in the home among them) by still.fail Helper's grant, never opened by the station: macOS asks on that machine's screen before it opens one, and the opening waits for as long as nobody answers |
| `GET /drive/list?root=&path=` | `{path, entries: [{name, dir, size, mtime, type}], truncated}`, folders first, names by number; past 50000 entries the first 50000 in that order |
| `GET /drive/stat?root=&path=` | one entry |
| `GET /drive/read?root=&path=&offset=&length=` | the bytes (at most 8 MB), `stillfail-total`, `stillfail-mtime`, `content-type` |
| `PUT /drive/upload?root=&path=&id=&offset=&total=(&replace=1)` | a part (the body); `{have, entry}`, `entry` once whole |
| `POST /drive/mkdir {root, path}` | the new folder's entry |
| `POST /drive/rename {root, from, to}` | within the root, nothing replaced |
| `POST /drive/remove {root, path, permanent?}` | to the machine's trash (macOS ~/.Trash, the freedesktop trash; another disk's own), a name there taken given a number; `no_trash` where none takes it (Windows), the asker then saying whether it goes for good (`permanent`: a folder with what it holds); a link as a link |
| `GET /drive/watch?root=&path=&id=` | `{changed}`: answered once something in the folder changes, else after 25 s; each asker's watch (`id`) kept a minute between its askings, a change meanwhile told at the next; a folder reached through still.fail Helper is not watched (`permission`: the client stops asking, and reads it when asked) |
| `POST /drive/zip {root, path}` | a folder zipped (as `stage` zips one) in a place of its own among the machine's temporary files, let go after an hour: `{root, path, name, size}`, read as any file of the drive is; members who may write |
| `POST /drive/stage {root, path}` | a file copied among the uploads (a clone where the disk can), answered as an upload is (`{name, path, size}`), for a message to send; at most 1 GB |

A refusal is `{error, code}` (`error` in the asker's language) with the code's
status: `invalid_request` 400, `not_a_root`/`not_found` 404,
`path_escape`/`protected`/`permission` 403,
`is_a_directory`/`not_a_directory`/`exists`/`upload_lost` 409, `too_large` 413,
`io` 500.

An upload is put together beside where it goes (`.stillfail-up-<id>.part`,
left out of listings) and renamed into place once whole, synced first; one left
unfinished for a day is removed the next time an upload starts in its folder. A
part that leaves a gap is refused `upload_lost` with `have`, where to go on from.

## Copying between stations (drive/transfers.ts, grants.ts, module.ts; api/routes/transfers.ts)

Files are copied (or moved) into a folder of a station from a folder of its own or of another station of the
workspace. The copy runs on the station the files go to, which reads them itself: from its own drive, or from the
other station over the station transport (docs/station-peers.md). No file goes through the device that asked, and the
copy goes on whatever becomes of that device: closed, asleep, away.

**Who may.** The person asking must be able to read the files where they are and write where they go, each station
checking it for itself as it does any request of theirs:

- The station the files are on signs a **grant** when the person asks (`POST /drive/grant {root, path, names, move?}`):
  it walks the names as that person reads them (a read-only member: only under a folder pinned, links out of it
  refused), and refuses a move to a read-only member (a move lets the originals go). The grant names the workspace it
  was asked in, the person, the folder and the names, whether it moves, and whether the person browses everywhere there;
  it is signed with a key of the station's own (`drive-grant.key` in its data directory, never sent anywhere) and good
  for seven days, so a copy that waited on a station away is taken up again with it.
- The station the files go to takes the copy only from a member who may write there (`POST /drive/transfers`), and only
  into a folder (as their uploads go).
- It reads the files with the grant (`drive.walk`, `drive.part`, `drive.release` on the bus). The station they are on
  checks its own signature, the workspace (the transport says which one the asking station asked in), that the path
  read is under one of the names granted (no `..`), and reads as that person would. The transport says which station
  asks; the grant is what says a person asked: no station reads another's files on its own say.

**What is copied.** The names are walked first: folders before what is in them, links not followed (a listing follows
them; a copy does not go where one leads), the station's own data left out as a listing leaves it out; at most
100 000 folders and files. A name already where they go was answered before the copy began (the page asks):
`replace` (the one there to its machine's trash first), `keep` (a name of its own beside it: `a 2.txt`, a folder
`b 2`), or `skip`; one not answered is refused (`exists`) rather than overwritten. Each file is put together beside
where it goes and put there whole, as an upload is (`.stillfail-up-<id>.part`, `upload`), a part at a time (8 MB from its
own drive; 256 KiB over the transport, taken from the file as it keeps coming after one request: from a station from
before, one request a part). A file that changes while it is read (its time moves) is read again from its start. A move lets the originals go (to their machine's trash; where
none takes them, removed) once every file is in place.

**Kept and taken up again.** The station runs its copies one at a time, in the order asked, each kept in its data
directory (`drive-transfers/<id>.json`) as it goes: a station that restarts takes the one under way up from the file
it was at, as far as its last part synced. One whose source cannot be read (its station away) fails; tried again
(`retry`), it goes on from where it was. Cancelled, it stops between parts; what is in place stays. Ended ones are
kept a day.

| Request | Answer |
|---|---|
| `POST /drive/grant {root, path, names, move?}` | `{grant, expires}`; refused as a read of those names is, and a move for a read-only member |
| `POST /drive/transfers {from: {station?, grant?, root, path, names}, to: {root, path}, move?, conflicts?}` | `{transfer}`; `from.station` another station's id (with its `grant`), none or this one's for its own drive; members who may write |
| `GET /drive/transfers` | `{transfers}`: the asker's own, newest first (without the list of what each copies) |
| `POST /drive/transfers/<id>/cancel`, `…/retry` | `{transfer}` |

A transfer as told: `{id, by, workspace, home, anywhere, move, from, to, conflicts, state (queued, walking, copying,
done, failed, cancelled), done, at, total, copied, count, files, current?, error?, createdAt, endedAt?}`. Each change is
told to the asker's own streams (`drive-transfers`, `{transfer}`).

Over the bus (with `{workspace, grant}`): `drive.walk {names?}` → `{items: [{path, dir, size}]}`; `drive.part {path,
offset, whole: true}` → `{size, mtime}` and the file from `offset` after it as it is read, its bytes ending early if
it changes (the reader asks again); without `whole` (a station from before asks so) → `{data (base64), size, mtime}`,
256 KiB of it; `drive.release {names}` → `{}` (a move's grant only). A refusal is the drive's
code and words (`permission: …`).

Not done yet: taking the contents a station already has (the same file elsewhere on it) instead of sending them; a copy
of a folder within one station by the disk's own clone.

## Core

- Topic `drive {station, root, path}`: the folder (`DriveFolder`), kept on the
  device (a station document), read again each time it is shown, and while shown
  again each time the station says something in it changed (`GET /drive/watch`); each entry
  with its `kind` (folder, video, audio, image, markdown, text, code, csv,
  html, pdf, subtitle, other: its mark), what a press on it does (`opens`:
  `folder` entered, `read`, `play`, `preview` as a chat's files are, else
  `save`), `sizeText`, `timeText`, and the folder's `countText`. A folder the station refuses (gone, out of its root) is
  let go and its error shown.
- Topic `drivePlace {station, root, path}`: where a file was left on this device
  (`{at, of, changed}`: a text's offset, a video's time in ms), null before.
- Operations: `drive.setRoots {roots}`, `drive.folders {path?}`,
  `drive.mkdir {root, path}`, `drive.rename {root, from, to}`,
  `drive.remove {root, path}`; each change reads its folders again before it
  answers. A name typed for a file or folder is asked first (`drive.check
  {text}`: `{problem}`, in words, null where it may be: not empty, no slash, not
  `.` or `..`); one kept beside another of its name (an upload's 保留两者) is
  named as the station keeps both (`drive.name {…, beside: true}`: `a 2.txt`).
- Calls: `drive.read {station, root, path, offset, length, progress?, stream?,
  keep?, mtime?, size?}` → `{type, total, mtime}`, the part as the answer's bytes
  (docs/client-core.md Protocol; with `progress`, values `{loaded}`, the part's
  bytes so far, as it comes; with `stream`, its bytes beside those values
  instead, as `station.file.part`'s). With `keep` (`file`: a file read whole or
  from its start; `played`: a video or song by its ranges) and the file's
  `mtime` and `size` as its folder says them, what is read is kept on the device
  and what is kept is answered without asking the station (client/core-ts
  src/drive-kept.ts, as Android's DriveCache.kt): a file changed since is read
  anew; past 512 MB of files or 1.5 GB of what was played, the least lately
  read go. `drive.kept.clear {}` lets all of it go; `cache.usage` counts it
  (`drive`). `drive.upload.part {station, root,
  path, id, offset, total, replace?}` with the part as its bytes → `{have, entry}` (a gap answers
  with `have`, the next part starts there; the last reads its folder again);
  `drive.refresh {station, root, path}`; `drive.place {station, root, path, at,
  of?}`.
- Topic `driveTransfers {workspace}` (views/transfers.ts): the person's copies into the workspace's stations, newest
  first (`DriveTransfersView`), each as the list shows it (`DriveTransferShown`: its title, where it goes in words,
  `statusText`, `progress`); held in memory as each station says them (read as its stream opens, told as they change).
- Calls: `drive.transfer {from: {station, root, path, names}, to: {station, root, path}, move?, conflicts?}`: another
  station's files granted there first (`POST /drive/grant`), then copied where they go (`POST /drive/transfers`); one
  within a station asked of it alone; `drive.transfer.cancel {station, id}`, `drive.transfer.retry {station, id}`.
- How it is browsed, the same for every client (views/browse.ts; what follows
  from what, drive-browse.ts; docs/client-core.md has each): view `driveBrowse
  {owner, place, view, station, root, path, write?}` (a place's folders in the
  order kept on the device, the count of those visible, what is chosen there, a tree's folders open, the
  columns' widths, the keys that act now) and `drive.browse` (a press, a key, a
  letter typed: what is chosen after it and what the client does), `drive.arrange`
  (the order, hidden files), `drive.name` (a new folder's name, a copy kept
  beside another), `drive.moves` (the renames a drag makes); the files' page's
  tabs, topic `filesTabs {workspace}` and `files.tabs`; a folder typed by its path,
  `files.go`; the stations with a drive, this machine's first, `stations` with
  `drive` and `here`. A client draws them and does what is answered.
- A station from before the drive has no `drive` in its overview: the clients
  offer nothing for it. One from before `anywhere` lends only its pinned folders.
- Into a chat's message (composer.ts): a file or folder dragged into the
  composer (from a list of a drive, or from Finder in the desktop app on a
  machine that is a station of the workspace) is named by its path
  (`ComposerFile.ref`, `mode: path`): the message says which station has it and
  where (`common.pathOn`), nothing goes up. `composer.mode {id, mode: file}`
  sends it as a file instead: the chat's own station copies it (`drive.stage`),
  another station's is read from there (`drive.read`) and sent up as a picked
  file is, one from Finder goes up from the page. A folder is only named.

## Clients

The files page opens the folder last left there, or a station's home. Its places
list has the person's favorites and the stations of the workspace (离线 beside
one while it is away). A folder's page has the way up to the home (or the disk's
top), a favorite action, and each row's path to copy; a row
dragged out carries the file and its path. A chat's 文件 tab
(web/src/pages/DriveTab.tsx) browses every station's files beside the chat, to
drag into the composer or add to the message; a new chat has the same tab
(open there, it stays open in the chat its first message makes). On both, a folder is worked
as in Finder (the core's `driveBrowse` and `drive.browse`, drawn by web/src/drive/browse.ts): a press chooses a row (⌘ adds or takes one
away, ⇧ the ones between), a double click or ⌘↓ opens it, ⌘↑ goes up, the arrows
move (→ and ← into and out of a folder in columns and a tree), typed letters go to
a name, ⏎ changes a name in place, space previews, ⌘⌫ deletes what is chosen,
⌘⇧N makes a folder (named as Finder names one, its name then changed). Hidden
files (a name starting with `.`) show only after ⌘⇧. ; the order (name, time,
size or kind, by the list's heads or the folder's right-click menu) and whether
they show are the person's, on the device (prefs `driveViews`); the count follows the entries shown. The files' page
starts as a list and a chat's files tab as columns, until another view is chosen. Names go in the order the device's language reads
them (the host's `collate`: 中文 by pinyin), by hand where it has none. A column's edge is
dragged as Finder's: that column wider or narrower (kept while the page is), with ⌥
every column (kept on the device, `driveViews.column`), a double click as wide as its
longest name. On the files' page what is
dragged onto a folder (its row, a column, the list) goes into it: a station's own
files moved (`drive.rename`; by the top of the disk for one from another folder
pinned; ⌥ copies them), another station's copied ("The files' page", below), the computer's put up, a folder of them made there and filled. A station's files go into a message from ＋'s Station
文件: the station homes and the same favorites, a folder entered, files (or the folder as a whole) ticked; each goes
in named by its path, or as a file where the chat says so, its card tapped to
switch it. The Android app stages a file of the chat's own station with
`drive.stage`, and reads one of another station's and sends it up.

The Android app keeps a file it has read on the phone (apps/android/…/drive/DriveCache.kt), so it opens again without
asking the station: by station, root and path, and by the `mtime` and `size` its folder says (a file changed is fetched
anew, the old one deleted; a read that finds it changed meanwhile starts again). Texts, pictures, PDFs and the rest are
kept whole (the reader's first 16 MB of a longer text), the least lately opened going past 512 MB; videos and songs by
the ranges played, in media3's cache, past 1.5 GB. Settings → storage shows both as one row, to clear.

## The files' page (web/src/pages/Files.tsx, FilesNav.tsx, FilesGo.tsx, Transfers.tsx, DrivePane.tsx)

On a wide screen the files' page is a window of Finder's over every station of the workspace:

- **Tabs** (drive/tabs.ts): each a folder of a station, or two side by side (⌘⌥D, the bar's button), to work between
  stations or folders; the side in front (underlined) is what the page's address says, where the keys go, and what a
  link, the sidebar or going back in history moves. ⌘T opens a tab where the front is (its × closes it: ⌘W is the window's), ⌘⇧[ and
  ⌘⇧] go along them; a folder's menu opens it in a new tab or on the other side. Kept on the device (prefs
  `filesTabs`, by workspace): 文件 in the rail comes back to the folder in front as it was left; the first time, to this
  machine's home (the desktop app on a station of the workspace).
- **The sidebar** (`apps/mbui/src/sfdesk/files_nav.mbt`): one personal favorites list of folders on any station, then each station with a drive
  (this machine marked 本机, its disk's fill, offline faint), its home on a press and its places under it opened.
  A folder is added from its menu, the picker, or a drag onto the list. The old station-pinned folders also appear as
  favorites, once each even if already saved through a different root. Removing a favorite records that choice on this
  device (`driveFavoritesHidden`, by workspace), so an old pin does not reappear when its station comes back online;
  adding it again clears that choice. Neither operation changes the station's pinned roots or a member's access. A
  favorite matching an old root opens through that root, preserving compatibility with station integrations that
  restrict which roots they can read.
- **Another station** from the start of a folder's trail: the same folder there where it has one, else its home (said
  so); ⌥ opens it in a new tab. **前往文件夹** (⌘⇧G): a path, the station's name before a colon if another
  (`mba:~/Projects`), `~` its home, a path without a slash in front under the folder shown; Tab completes a folder's
  name.
- **The preview** (⌘⇧P, the bar's button; a chat's 文件 tab has it under its list): the one file chosen, a picture
  whole (up to 32 MB), the start of a text (Markdown rendered), what plays or needs a page of its own by how to open it;
  its size, time, station and path.
- **Copying and moving**: what is dragged onto a folder (a row, a column, the list, a folder in the sidebar) goes into
  it: across stations a copy (⌘ held: a move), within one a move (⌥: a copy), as Finder does across disks and within
  one; 复制到… and 移动到… on a menu pick the folder in a dialog of every station's. A name already there is asked
  about first (replace, keep both, skip; for all the rest at once). A move within a station by a root both places are
  under is a rename, at once; anything else a copy as above. The bar's 传输 says how many go and how far; its list
  stops one, tries one that failed again, or shows the folder of one done. A station from before copies takes none
  (`transfers` absent): what is dragged onto it is not taken, and 复制到… says it needs an update.
