// What the readers answer, by name: each module of reads adds its own. Every op runs in a reader thread over a
// read-only store, with the request's language set (`setSpoken`), and returns a JSON value.
import type { Store } from "./store.ts";
import { archivedPage, chatMarks, chatRows, chats, entries, letters, setSpoken, sharedChatRows } from "./views.ts";
import { usageOps } from "./ops-usage.ts";
import { sessionOps } from "./ops-sessions.ts";
import { saidNotices, turnNotices } from "./notices.ts";
import { runtimeList } from "./runtime-view.ts";
import { changedOf } from "./digest.ts";
import { publishDraft } from "./publish.ts";

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
  /// The same sidebar items (`chatRows`) for each of several viewers (one person's devices in two languages or
  /// workspaces), in one read: what the first read in serves the others.
  chatRowsOf: (store, a) => a.viewers.map((v: { viewer: any; lang: any }) => (setSpoken(v.lang), chatRows(store, v.viewer, a.sessions, a.threads))),
  entries: (store, a) => entries(store, a.viewer, a.thread, a.params),
  letters: (store, a) => letters(store, a.viewer, a.thread, a.params),
  ...usageOps,
  ...sessionOps,
  turnNotices: (store, a) => turnNotices(store, a.key, a.since, a.ended, a.lang),
  saidNotices: (store, a) => saidNotices(store, a.thread, a.entries, a.since, a.lang),
  /// A chat as a published snapshot would show it (api/routes/publish.ts).
  publishDraft: (store, a) => publishDraft(store, a, a.lang),
  /// What of a list (the read `op` with `args`) a client holding `held` does not hold as it is (POST /changed/<list>).
  changed: (store, a) => changedOf(runtimeList(a.op, ops[a.op]!(store, a.args), a.runtimes), a.id, a.held),
};
