// What of the station's chats a viewer sees (docs/multi-workspace.md): those of their own workspace, but for those private
// to other people (docs/private-chats.md). A request that names a session, a chat, a job or a published snapshot of
// another workspace, or private to others, is answered as one naming what is not there.
import { percentDecode } from "./request.ts";
import { type InWorkspace, seesChat, seesMembers } from "../store/rows.ts";
import type { Store } from "../store/store.ts";

/// Whether `viewer` sees a session (one not there: the home workspace's).
export const sessionSeen = (store: Store, viewer: InWorkspace, key: string) => seesChat(viewer, store.getSession(key) ?? { ws: null });

/// Whether `viewer` sees a thread (store/rows.ts `seesMembers`).
export const threadSeen = (store: Store, viewer: InWorkspace, id: number): boolean => seesMembers(viewer, store.threadSessions(id).map((m) => store.getSession(m.session)));

/// Whether `viewer` sees a job: its session is theirs.
export const jobSeen = (store: Store, viewer: InWorkspace, id: string) => {
  const job = store.getJob(id);
  return job === null || sessionSeen(store, viewer, job.sessionKey);
};

/// What names one of them: `/sessions/:key…`, `/threads/:id…`, `/jobs/:id…`, `/published/:id`.
const NAMED = /^\/*(sessions|threads|jobs|published)\/+([^/]+)/;
/// admin/mod.rs `segment_decode`, as the routes read a key.
const segment = (s: string) => percentDecode(s.replace(/\+/g, "%2B"));

/// The 404 a request is answered with when what its path names is there but of another workspace than the viewer's;
/// null otherwise (what is not there at all is the route's to say).
export function elsewhere(store: Store, path: string, viewer: InWorkspace): string | null {
  const named = NAMED.exec(path);
  if (named === null) return null;
  const [, kind, raw] = named;
  const id = segment(raw!);
  switch (kind) {
    case "sessions":
      return store.getSession(id) !== null && !sessionSeen(store, viewer, id) ? `unknown session ${id}` : null;
    case "threads": {
      const n = /^[+-]?\d+$/.test(id) ? Number(id) : NaN;
      return Number.isSafeInteger(n) && store.getThread(n) !== null && !threadSeen(store, viewer, n) ? `unknown thread ${id}` : null;
    }
    case "jobs":
      return jobSeen(store, viewer, id) ? null : `no job ${id}`;
    default: {
      const p = store.published(percentDecode(raw!));
      return p !== null && store.getThread(p.thread) !== null && !threadSeen(store, viewer, p.thread) ? `no published snapshot ${id}` : null;
    }
  }
}
