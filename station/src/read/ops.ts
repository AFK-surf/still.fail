// What the readers answer, by name: each module of reads adds its own. Every op runs in a reader thread over a
// read-only store, with the request's language set (`setSpoken`), and returns a JSON value.
import type { Store } from "./store.ts";
import { chatRows, chats, entries, letters } from "./views.ts";
import { usageOps } from "./ops-usage.ts";
import { sessionOps } from "./ops-sessions.ts";
import { saidNotices, turnNotices } from "./notices.ts";
import { runtimeList } from "./runtime-view.ts";
import { changedOf } from "./digest.ts";
import { publishDraft } from "./publish.ts";

export type ReadOp = (store: Store, args: any) => unknown;

export const ops: Record<string, ReadOp> = {
  chats: (store, a) => chats(store, a.viewer, a.archived),
  chatRows: (store, a) => chatRows(store, a.viewer, a.sessions, a.threads),
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
