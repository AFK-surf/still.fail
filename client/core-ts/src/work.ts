// What the core's work on a change took, counted rather than timed, so a test holds it to what changed (test/work.test.ts):
// a change to one item of a list of 1000 must cost what it costs in a list of 100. Each count is of one kind of work
// that follows the size of what it is done over; a part that keeps its objects where nothing changed is not counted
// again for them.
export const work = {
  /// Objects and arrays `share` compared (collections.ts): what the store's new value was matched against its last over.
  compared: 0,
  /// Of those, the ones equal to the last but made again: what a source could have kept.
  remade: 0,
  /// Item keys written out to match a keyed list's items (an item kept from the last value is not written again).
  keyed: 0,
  /// Bytes counted to weigh ops against the value they make (`heavier`).
  weighed: 0,
  /// Items of keyed lists made as they go out (output.ts), not taken as they went out last.
  shaped: 0,
  /// Values made whole as they go out (output.ts `shape`), not taken as they went out last (`kept`).
  shapes: 0,
  /// Rows of a log (a thread's entries) read from the database rather than taken as parsed (db/account.ts).
  logRows: 0,
  /// Rows (chats, sessions' summaries, threads, jobs) whose JSON was read from the database for a row kept by its key
  /// (db/account.ts `#cached`, `#byKey`): parsed, or read for nothing where the row was kept already.
  rowJson: 0,
  /// A station's chat rows made of what they are made of (station/rows-made.ts, through its RowsMemo): those whose
  /// parts changed, the rest kept as made before.
  chatRowsMade: 0,
  /// Chat rows serialised as they are written or compared with what is written (db/account.ts `#chatCols`): those given
  /// that are not the row written there before.
  chatRowsSerialised: 0,
  /// Numbers of a log's items read from the database (which it holds, to find what to read).
  logNumbers: 0,
  /// Items a log's span (its first, its last, how many) was counted over in the database rather than kept.
  logSpans: 0,
  /// Records a chat list made into rows, and rows it put into its days (views.ts #chats): those that changed, where
  /// the list is made from the last one.
  listed: 0,
  /// Rows a workspace's mark made what they say of themselves of (views/marks.ts `rowMade`): those that changed, the
  /// rest kept with the row.
  marked: 0,
  /// Workspaces' marks made (views/marks.ts `workspaceMark`): each made again only as what it is made of changed.
  workspaceMarks: 0,
  /// Rows a chat list made of its records (views.ts #chatRow): those something shows, each once while its record is as
  /// it was.
  rows: 0,
  /// Records cloned whole into a row (views.ts #chatRow `whole`: a chat's own row, made for one chat at a time). A list's
  /// rows clone none (#listRow takes of its record what it holds, the values shared).
  rowsCloned: 0,
  /// What is kept beside its record (db/kept.ts KEPT), each declaration's: values read back as kept (`<name>Kept`:
  /// neither made nor their records read), put beside their records (`Written`: as these are written, or after a reader
  /// made them as it read them), and made by the views as their records were written (`Made`).
  listRowKept: 0,
  listRowWritten: 0,
  listRowMade: 0,
  overviewFitKept: 0,
  overviewFitWritten: 0,
  overviewFitMade: 0,
  profileRowKept: 0,
  profileRowWritten: 0,
  profileRowMade: 0,
  /// Items of keyed lists put through their shape as they go out (output.ts), not taken as made beside them
  /// (conform.ts shapedBeside).
  conformed: 0,
  /// Stations' accounts' rows made of their parts (views.ts #profileRowsMade), as read or as written: each profile
  /// decorated.
  profileRows: 0,
  /// Values copied, decorated and put through their shape whole as they go out (output.ts), not taken as made beside
  /// them (conform.ts shapedBeside: the accounts' rows, views.ts `profiles`).
  wholeShaped: 0,
  /// What a chat's row offers only as it is pressed, held, swiped or pointed at, made of its record (views.ts #chatRow
  /// whole, #rowMenu): its menu's (who may share it, publish it, its links in Slack and Feishu), its swipe's question, its
  /// watch's words. A list's rows make none: a chat's whole row (`chatRow`) does, made for one chat at a time.
  rowMenus: 0,
  swipeAsks: 0,
  watches: 0,
  /// Chats' pages made (views.ts `chat`): each made again only as something it is made of changed, not as a UI's focus
  /// moves or a pref it does not read is written.
  chats: 0,
  /// A chat's messages made as its page shows them (views.ts `#chat`, shownMessage): those of its window, each made
  /// again only as it or what it is shown by changed.
  messages: 0,
  /// Topics' values hashed for their token (store.ts, digest.ts `token`): those that are no object alone (a value that
  /// is one goes by the object itself, nothing of it read), as a client lets one go keeping it and asks it again.
  versions: 0,
  /// A chat's messages looked through for the chats they link to (views.ts #linkedStations), for the lists it watches:
  /// once its first value has gone out, not before.
  linkScans: 0,
  /// Columns of stations' overviews' parts read from the database and parsed (db/account.ts `#overviewColumn`), not
  /// taken as kept, and how many characters they came to: what a list, a row or a page reads of an overview, never the
  /// whole of it.
  overviewParts: 0,
  overviewPartChars: 0,
  /// Stations' whole overviews read from the database and parsed (db/account.ts `stationDoc`), not taken as kept.
  overviewsRead: 0,
  /// Stations' whole overviews decorated and shaped (views.ts #stationShownOf), not taken as made for their record.
  overviews: 0,
  /// What the workspace's profiles read of a station's overview (its kept part, station_part.profiled) decorated
  /// (views.ts #stationShownOf `profile`), not taken as made for it: never the whole overview.
  profiledParts: 0,
  /// Stations' models listed from an overview's profiles (views/models.ts `models`), each with what every account of it
  /// runs and has left: a new chat's page makes its one station's, a model control's panel every station's it could
  /// borrow from too.
  models: 0,
  /// Models a control's panel annotated with how each runs picked there (choose.ts #pick: each option's `usual`, its
  /// words, its star): a panel's, never a page's.
  annotated: 0,
};

export type Work = typeof work;

/// What was only looked at, to find it as it was: one comparison an item, so it follows how much is held, as a change's
/// `work` must not. Counted apart, for tests to hold: a change of one chat told by a station that makes its list looks
/// at none of it (test/rows-changed.test.ts).
export const glanced = {
  /// Chat rows a station's list was given that were the row written there before, at the same place: taken as written,
  /// neither serialised nor compared (db/account.ts `setChats`).
  chatRowsSame: 0,
  /// Chat rows a station's list was given whole (db/account.ts `setChats`): each looked at for its place and whether it
  /// is the one written.
  chatRowsWalked: 0,
  /// Chat rows put in this device's words as a list given whole (data.ts `inWords`).
  chatRowsWorded: 0,
  /// Chat rows a station's sidebar was made of as a whole (station/rows-made.ts `rowsShared`, `rowsMade`): each made, or
  /// taken as made before.
  chatRowsMapped: 0,
  /// Entries of a station's marks walked to make the viewer's own of them (station/rows-made.ts `OwnHeld`).
  marksWalked: 0,
};

/// What the views, the store and what goes out walked in memory: items looked at, each a plain count where the walk is,
/// whatever topic it is for. A change of one thing must walk what changed, not what is held or shown
/// (test/view-work.test.ts holds every cause of real-size-asked.ts `CAUSES` to it, with what is shown three times as
/// large and with three times the chats). What is found the same object as before costs one comparison, counted in
/// `same` alone: the other counts are of what is walked past it.
export const walked = {
  /// Reads a computed or an observer tracked (reactive.ts `tracked`): each signal or computed read, each time.
  reads: 0,
  /// Topics' values made again by their source (store.ts #compute).
  recomputes: 0,
  /// Objects and arrays collections.ts `share` went into past the same object, and the items of each array it mapped
  /// between the same objects at its start and its end (a keyed list's last items there each put in its map as well).
  shared: 0,
  /// Objects and arrays util.ts `equal` compared past the same object.
  equaled: 0,
  /// Items a keyed list's diff took the keys of (collections.ts `list`): of both lists, between the same objects at their
  /// start and their end.
  diffed: 0,
  /// Items of keyed lists output.ts #build put together or looked up in its memo by their key: those not the object
  /// an item was made of before.
  built: 0,
  /// Objects and arrays output.ts `copy` walked that had not gone out as they are.
  copied: 0,
  /// Values conform.ts `fit` visited that had not gone out as they are.
  fitted: 0,
  /// Items found the same object as the one before, taken as they were with one comparison of two references (or one
  /// lookup by the object): of a list `share` or a keyed list's diff trims at its start and its end, an item output.ts
  /// finds made of the very object, a value `copy` or `fit` finds gone out. It follows what is shown, so it is printed and
  /// not held (test/view-work.test.ts).
  same: 0,
};

export type Walked = typeof walked;

/// Whose walking it is: the topic made or sent now (store.ts sets it as it makes and sends one, `walkingAs`), and, where
/// a test asks (`walkingBy`), each topic's counts beside the totals: what was walked between two switches of the topic
/// is counted to the one walking then, the walks themselves counting the totals alone.
export const walking: { topic: string; by: Map<string, Walked> | null } = { topic: "", by: null };
/// The totals as the topic walking now took over (while `walking.by` is set).
let walkedAt: Walked = { ...walked };

/// The topic walking now becomes `topic`, and the one before is given back (to be set again as `topic` is done). Where
/// a test counts by topic, what was walked since the last switch is counted to the one before. Outside tests it only
/// sets the topic.
export function walkingAs(topic: string): string {
  const was = walking.topic;
  const by = walking.by;
  if (by !== null) {
    let w: Walked | undefined;
    for (const k of Object.keys(walked) as (keyof Walked)[]) {
      const n = walked[k] - walkedAt[k];
      if (n === 0) continue;
      if (w === undefined && (w = by.get(was)) === undefined) by.set(was, (w = { reads: 0, recomputes: 0, shared: 0, equaled: 0, diffed: 0, built: 0, copied: 0, fitted: 0, same: 0 }));
      w[k] += n;
    }
    walkedAt = { ...walked };
  }
  walking.topic = topic;
  return was;
}

/// Counts by topic from now into `by` (a test's), or no more (null): what was walked till now counted as it was.
export function walkingBy(by: Map<string, Walked> | null): void {
  walkingAs(walking.topic);
  walking.by = by;
  walkedAt = { ...walked };
}

/// What was counted since `from` (a copy taken before).
export function workSince(from: Work): Work {
  const out = { ...work };
  for (const k of Object.keys(out) as (keyof Work)[]) out[k] -= from[k];
  return out;
}
