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
- **Pinned folders** (`drive.roots` in config.json) are the list everyone sees
  first (the files' sidebar, a chat's 文件 tab); any member who may write pins
  and unpins them. **Read-only members** (viewers) reach only these, and only
  browse and read (the admin API refuses their writes).
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
  for from the station's page or by an agent counts the same. Its Allow has the
  helper open the folder, and macOS asks. One refused before opens System
  Settings › Files and Folders instead, where the helper has a switch for it.
  The window tells the station when a grant changes, and the roots are told
  again (`unreadable` becomes `ok`). A pinned root in such a folder is
  `unreadable` until the helper has the grant.
- Agents are not affected: their commands still run under the station's
  launcher, which macOS keeps out of these folders as before (an agent whose
  chat starts there is told so, `station.session.cwdDeniedMac`).

## Station (station/src/drive/drive.ts, api/routes/drive.ts)

| Request | Answer |
|---|---|
| `GET /drive` | `{roots: [{path, name, state}], manage, write, anywhere?, home?, trash?, watch, zip?}` (also in the overview as `drive`; `state` `unreadable` for a folder macOS protects until still.fail Helper has its grant) |
| `PUT /drive/roots {roots}` | the folders pinned, by any member who may write; each new one must be there, a folder, none of the station's data |
| `GET /drive/folders?path=` | members who may write: the folders in `path` (the home when empty), to pick one to pin |
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

## Core

- Topic `drive {station, root, path}`: the folder (`DriveFolder`), kept on the
  device (a station document), read again each time it is shown, and while shown
  again each time the station says something in it changed (`GET /drive/watch`); each entry
  with its `kind` (what opens it: folder, video, audio, image, markdown, text,
  code, csv, html, pdf, subtitle, other), `sizeText`, `timeText`, and the
  folder's `countText`. A folder the station refuses (gone, out of its root) is
  let go and its error shown.
- Topic `drivePlace {station, root, path}`: where a file was left on this device
  (`{at, of, changed}`: a text's offset, a video's time in ms), null before.
- Operations: `drive.setRoots {roots}`, `drive.folders {path?}`,
  `drive.mkdir {root, path}`, `drive.rename {root, from, to}`,
  `drive.remove {root, path}`; each change reads its folders again before it
  answers.
- Calls: `drive.read {station, root, path, offset, length, progress?}` →
  `{type, total, mtime, bytes}` (base64; with `progress`, values `{loaded}`,
  the part's bytes so far, as it comes); `drive.upload.part {station, root,
  path, id, offset, total, replace?, bytes}` → `{have, entry}` (a gap answers
  with `have`, the next part starts there; the last reads its folder again);
  `drive.refresh {station, root, path}`; `drive.place {station, root, path, at,
  of?}`.
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

On a wide screen the rail's 文件 (web/src/Rail.tsx) goes to `/w/<ws>/files`,
which opens the first folder pinned (else the first station's home); the
sidebar beside the drive's pages lists each station's home and the folders
pinned, the station's name at the end of each. A folder's page has the way up
to the home (or the disk's top), a pin, and each row's path to copy; a row
dragged out carries the file and its path. A chat's 文件 tab
(web/src/pages/DriveTab.tsx) browses every station's files beside the chat, to
drag into the composer or add to the message. On both, a folder is worked
as in Finder (web/src/drive/browse.ts): a press chooses a row (⌘ adds or takes one
away, ⇧ the ones between), a double click or ⌘↓ opens it, ⌘↑ goes up, the arrows
move (→ and ← into and out of a folder in columns and a tree), typed letters go to
a name, ⏎ changes a name in place, space previews, ⌘⌫ deletes what is chosen,
⌘⇧N makes a folder (named as Finder names one, its name then changed). Hidden
files (a name starting with `.`) show only after ⌘⇧. ; the order (name, time,
size or kind, by the list's heads or the folder's right-click menu) and whether
they show are the person's, on the device (prefs `driveViews`). On the files' page what is
dragged onto a folder (its row, a column, the list) goes into it: a station's own
files moved (`drive.rename`; by the top of the disk for one from another folder
pinned), the computer's put up, a folder of them made there and filled. The phone reaches a drive from
its station's page, and puts a station's files into a message from ＋'s Station
文件 (web/src/mobile/StationFiles.tsx, apps/android/…/screens/StationFiles.kt):
the places, a folder entered, files (or the folder as a whole) ticked; each goes
in named by its path, or as a file where the chat says so, its card tapped to
switch it. The Android app stages a file of the chat's own station with
`drive.stage`, and reads one of another station's and sends it up.

The Android app keeps a file it has read on the phone (apps/android/…/drive/DriveCache.kt), so it opens again without
asking the station: by station, root and path, and by the `mtime` and `size` its folder says (a file changed is fetched
anew, the old one deleted; a read that finds it changed meanwhile starts again). Texts, pictures, PDFs and the rest are
kept whole (the reader's first 16 MB of a longer text), the least lately opened going past 512 MB; videos and songs by
the ranges played, in media3's cache, past 1.5 GB. Settings → storage shows both as one row, to clear.
