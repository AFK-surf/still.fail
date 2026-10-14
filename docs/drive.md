# A station's drive

A station lends its members folders of its machine: they browse them, read and
play what is in them, and upload, rename and remove. It is zdrive
(`zzj3720/zdrive`) brought into still.fail: zdrive's ops and path sandbox, over
the members' link the station already has (no pairing, no allowlist of its own,
no transport of its own).

## Who may do what

- **Which folders**: the workspace's owners and admins name them, in the
  station's settings (`drive.roots` in config.json). None by default: a station
  lends nothing until someone names a folder.
- **Members** browse and change what is under them; **read-only members**
  (viewers) only browse and read (the admin API refuses their writes).
- Every path is relative to a root and stays in it: `..` is refused, a link that
  leads out is refused (and not listed), and the station's own data (its data
  directory, config, the profiles' homes, the machine's runtime logins) is never
  reachable even under a root, as for the device tools.
- On macOS a station launchd runs may not read Documents, Desktop, Downloads or
  removable volumes: such a root is listed with `state: unreadable`.

## Station (station/src/drive/drive.ts, api/routes/drive.ts)

| Request | Answer |
|---|---|
| `GET /drive` | `{roots: [{path, name, state}], manage, write}` (also in the overview as `drive.roots`) |
| `PUT /drive/roots {roots}` | owners and admins; each new one must be there, a folder, none of the station's data |
| `GET /drive/folders?path=` | owners and admins: the folders in `path` (the home when empty), to pick a root |
| `GET /drive/list?root=&path=` | `{path, entries: [{name, dir, size, mtime, type}], truncated}`, folders first, names by number |
| `GET /drive/stat?root=&path=` | one entry |
| `GET /drive/read?root=&path=&offset=&length=` | the bytes (at most 8 MB), `stillfail-total`, `stillfail-mtime`, `content-type` |
| `PUT /drive/upload?root=&path=&id=&offset=&total=(&replace=1)` | a part (the body); `{have, entry}`, `entry` once whole |
| `POST /drive/mkdir {root, path}` | the new folder's entry |
| `POST /drive/rename {root, from, to}` | within the root, nothing replaced |
| `POST /drive/remove {root, path}` | a folder with what it holds; a link as a link |

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
  device (a station document), read again each time it is shown; each entry
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
- Calls: `drive.read {station, root, path, offset, length}` →
  `{type, total, mtime, bytes}` (base64); `drive.upload.part {station, root,
  path, id, offset, total, replace?, bytes}` → `{have, entry}` (a gap answers
  with `have`, the next part starts there; the last reads its folder again);
  `drive.refresh {station, root, path}`; `drive.place {station, root, path, at,
  of?}`.
- A station from before the drive has no `drive` in its overview: the clients
  offer nothing for it.

## Clients

On a wide screen the rail's 文件 (web/src/Rail.tsx) goes to `/w/<ws>/files`,
which opens the first station lending folders; the sidebar beside the drive's
pages lists every station's folders under its name. The phone reaches a drive
from its station's page.
