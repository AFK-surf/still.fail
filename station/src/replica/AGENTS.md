# The copies of a station's conversations (for agents)

Losing one machine does not lose a workspace's conversations (the user, 2026-11-09). What must survive of a station's
chats (their threads, entries and letters, their sessions, turns and each viewer's marks, and the files attached to
them) is copied, a workspace at a time, to the stations that keep it, and a new
station takes it back in place of a lost one. Transcripts, usage, accounts and working directories are the machine's
own and are not copied: a chat taken back goes on afresh, as one moved to another account does (a station retired,
below, sends them along).

- One export, off the main thread (`export.ts`): the MoonBit program's (`station/mb/src/replica`, started by `runner.ts`
  `exportThread`) where it is built, else a worker thread's (`worker.ts`); a restore the same (`restore.ts`
  `takeBackSoon`). The program writes and reads what the TypeScript does, line for line, so either takes up the
  other's state and copies (`station/test/mb-replica.test.ts` holds them to each other). It reads stillfail.db only: immutable batches
  (`format.ts`), a generation of them per workspace, `head.json` written last. What changed is found by what the tables
  already give (the rowid of what is only added to, an index, the store's own changes told to it, a digest of what was
  written in its own `export.db`), never by a trigger or a statement on the main thread's write path
  (`replica-export-bounded.test.ts` counts them).
- The stations that keep them keep the batches and files as opaque files (`places.ts`): two other stations of the same
  workspace (the two whose rendezvous hash with it is highest, `peers.ts keepers`, worked out in each station from its
  roster). Nothing about it is set by anyone, and the app shows it as one row (the user, 2026-11-10: 「按最简单的交互方式
  做」; a folder of one's own was taken out). There is no follower database and no merging: only a
  restorer reads inside a batch (`restore.ts`), into a station with no chats of its own (or one a station was retired
  into, below), before its store opens.
- A pass and the exporter's state (`export.db`) are one transaction, committed after the head that names its batches.
  A batch holds at most BATCH_BYTES; folds and restores go through SQLite on disk and stream files, so their heap
  does not grow with the copy (`replica-heap-bounded.test.ts` runs them in a 24 MB worker heap).
- What a place holds is kept (`places.ts Known`) and only the new batch and head are sent; its listing is asked only
  as the station starts, on hello, after a failure and on handover. While a keeper is not reached the next station in
  the rendezvous order holds the copy meanwhile (`replica-stations.test.ts` counts the requests).
- A restore's three steps (rows, files, `formerly`) are each safe to run again; its outcome stays (`restore.ts outcomeFile`)
  for the settings after the restart. What it brought is let go only once its files are placed (or its rows never went
  in): rows in and files not, the next start places them. It folds the batches on disk first and puts each row that is left
  in once, so the store's triggers see each final row once: restored from the batches as written or from the
  generation folded whole, every table of the database is the same (`replica-export.test.ts`). It is refused early, and again before the restart, on a station that has a chat
  of its own, but for a retired station's.
- A workspace's batches hold only its own chats; a station that leaves a workspace deletes what it kept of it. A
  copy no longer a station's to keep goes only once those that should keep it say they hold as much.
- A station rolled back (a backup put back) finds a place holding more than it has (`places.ts behind`): it begins a
  new generation and the place keeps both; nothing is merged or dropped.
- A station retired from a workspace (`retire.ts`; the user, 2026-11-13: 「搬家主要考虑的场景是要废弃掉一个 station」,
  「要允许用户选择目标迁移 station」) hands all its chats there to the station a person picked, which may have chats of
  its own: what is hard to move is left to what already makes it, never rewritten by hand (「避免脚本乱改改错」). The app
  shows first what it would move (`GET /retire/preview`, found by the same functions the retirement uses). Each
  session's room whole (an archived one's packed workspace with it; `footprint.ts roomOf`, a session whose directory is
  not the station's own counted and left) and its agents' transcripts go by their bytes to the same places under the
  other's data directory, only under `sessions/` and `transcripts*/` (`carry-worker.ts`): a checkout's files as git
  lists them (`rebuildable` stays behind), its own `.git` as files, a repository in it gone into; a linked worktree is
  made again there by git (its remote fetched and pruned first, a bundle of the commits no remote has, `git worktree add`
  and `repair`; one that cannot be keeps its bundle beside it; not begun where that station has no git). A station has
  a million files: nothing of them is one object on a main thread or in one message (a list a session on disk, an
  index of the lists, `retire.lacking` a bounded batch of hashes at a time; `replica-retire.test.ts` counts them). Every
  file is checked by its hash as it is written there, and copied into place (a clone where the disk makes one). The
  copy is put in beside the other's chats by the same restore (`build`'s `merge`: each thread an id there, a
  platform's thread both followed the one there with its own log, a still.fail chat of the same ts given the next free
  one, the connects' ids and the sessions' `ws` as there), after which that station is this one too (`formerly`), each
  moved chat's agent told once (`moved_notes`); what it tells the retired station goes to that one itself
  (mesh/bus.ts `askItself`, as a request naming it would come back to itself). The chats stop (sessions/hub.ts
  `quiet`, every chat of the workspace, the home one's too, and their jobs; for good once done, across restarts) only
  for what changed since the first sending; what their platforms say meanwhile is kept and goes there first
  (connects/workspace.ts `moveAll`; a Comma connect's, which no station routes to another, is refused unkept, as
  `Retiring`). Retired from its home workspace, its accounts move there before the connects (share/index.ts
  `moveProfile`; one that cannot is said, `accountsLeft`); the connects move last, the chats then out of sight here
  (`retiredWs`); the app then takes the station out. Each side says what it does and where it stands (`retire.begin`,
  `.take`, `.took`, `.failed`, `.drop`), no polling; a copy the other could not put in, or whose restore never said how
  it went after two starts, is tried again only as a person asks; a cancel answers at once, is refused once the other
  took the chats, and one made while the other is not reached before it was asked to take them is told it once it is
  up. Build output, and the browser's sign-ins stay behind; jobs and services too, their agents told which.
- Not here, by the owner's decision (2026-11-09): reading a chat from a copy while its station is away, going on with a
  chat on another station while both are up, signed heads, a lock entry for a replacement.
