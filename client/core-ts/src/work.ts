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
  /// What a chat's row offers only as it is pressed, held, swiped or pointed at, made of its record (views.ts #chatRow
  /// whole, #rowMenu): its menu's (who may share it, publish it, its links in Slack and Feishu), its swipe's question, its
  /// watch's words. A list's rows make none: a chat's whole row (`chatRow`) does, made for one chat at a time.
  rowMenus: 0,
  swipeAsks: 0,
  watches: 0,
  /// Chats' pages made (views.ts `chat`): each made again only as something it is made of changed, not as a UI's focus
  /// moves or a pref it does not read is written.
  chats: 0,
  /// Topics' values hashed whole for their version (store.ts, digest.ts `version`): as a client lets one go keeping it,
  /// and as it asks it again where what it holds is not remembered.
  versions: 0,
  /// Stations' whole overviews read from the database and parsed (db/account.ts `stationDoc`), not taken as kept.
  overviewsRead: 0,
  /// Stations' whole overviews decorated and shaped (views.ts #stationShownOf), not taken as made for their record.
  overviews: 0,
  /// Stations' models listed from an overview's profiles (views/models.ts `models`), each with what every account of it
  /// runs and has left: a new chat's page makes its one station's, a model control's panel every station's it could
  /// borrow from too.
  models: 0,
  /// Models a control's panel annotated with how each runs picked there (choose.ts #pick: each option's `usual`, its
  /// words, its star): a panel's, never a page's.
  annotated: 0,
};

export type Work = typeof work;

/// What was counted since `from` (a copy taken before).
export function workSince(from: Work): Work {
  const out = { ...work };
  for (const k of Object.keys(out) as (keyof Work)[]) out[k] -= from[k];
  return out;
}
