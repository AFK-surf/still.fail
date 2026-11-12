# The copies of a station's conversations (for agents)

Losing one machine does not lose a workspace's conversations (the user, 2026-11-09). What must survive of a station's
chats (their threads, entries and letters, their sessions, turns and each viewer's marks, and the files attached to
them) is copied, a workspace at a time, to the stations that keep it, and a new
station takes it back in place of a lost one. Transcripts, usage, accounts and working directories are the machine's
own and are not copied: a chat taken back goes on afresh, as one moved to another account does.

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
  restorer reads inside a batch (`restore.ts`), into a station with no chats of its own, before its store opens.
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
  of its own.
- A workspace's batches hold only its own chats; a station that leaves a workspace deletes what it kept of it. A
  copy no longer a station's to keep goes only once those that should keep it say they hold as much.
- A station rolled back (a backup put back) finds a place holding more than it has (`places.ts behind`): it begins a
  new generation and the place keeps both; nothing is merged or dropped.
- Not here, by the owner's decision (2026-11-09): reading a chat from a copy while its station is away, going on with a
  chat on another station, signed heads, a lock entry for a replacement, transcripts.
