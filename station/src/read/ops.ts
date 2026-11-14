// What the readers answer, by name: each module of reads adds its own. Every op runs in a reader thread over a
// read-only store, with the request's language set (`setSpoken`), and returns a JSON value.
import type { Store } from "./store.ts";
import { archivedPage, chatMarks, chatRows, chats, entries, letters, setSpoken, sharedChatRows, sharedOf } from "./views.ts";
import { usageOps } from "./ops-usage.ts";
import { sessionOps } from "./ops-sessions.ts";
import { saidNotices, turnNotices } from "./notices.ts";
import { runtimeList } from "./runtime-view.ts";
import { changedOf } from "./digest.ts";

export type ReadOp = (store: Store, args: any) => unknown;

/// `?page=` of the archive: where the page before ended (`<when>:<key or chat id>`, as `archivedPage` says it), or ""
/// for its first.
const cursorOf = (page: string): [number, string] | null => {
  const at = page.indexOf(":");
  const when = Number(page.slice(0, at));
  return at > 0 && Number.isSafeInteger(when) ? [when, page.slice(at + 1)] : null;
};

export const ops: Record<string, ReadOp> = {
  chats: (store, a) => (a.archived && typeof a.page === "string" ? archivedPage(store, a.viewer, cursorOf(a.page)) : chats(store, a.viewer, a.archived)),
  chatRows: (store, a) => chatRows(store, a.viewer, a.sessions, a.threads),
  chatMarks: (store, a) => chatMarks(store, a.viewer, a.scope ?? null),
  sharedChats: (store, a) => sharedChatRows(store, a.viewer, a.sessions, a.threads),
  /// The chat list (or the rows some sessions and threads touch) as told to every stream that makes its sidebar of it.
  sharedOf: (store, a) => sharedOf(store, a.sessions, a.threads),
  entries: (store, a) => entries(store, a.viewer, a.thread, a.params),
  letters: (store, a) => letters(store, a.viewer, a.thread, a.params),
  ...usageOps,
  ...sessionOps,
  turnNotices: (store, a) => turnNotices(store, a.key, a.since, a.ended, a.lang),
  saidNotices: (store, a) => saidNotices(store, a.thread, a.entries, a.since, a.lang),
  /// What of a list (the read `op` with `args`) a client holding `held` does not hold as it is (POST /changed/<list>).
  changed: (store, a) => changedOf(runtimeList(a.op, ops[a.op]!(store, a.args), a.runtimes), a.id, a.held),
};
