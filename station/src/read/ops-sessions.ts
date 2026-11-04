// The reads of sessions, threads and jobs (src/api/routes/sessions.ts asks them), each with the request's `lang`.
import type { ReadOp } from "./ops.ts";
import { job, jobLog, openJobs } from "./jobs.ts";
import { firstText, getSession, getThread, lastSaid, listThreads, messagesBefore, threadSessions } from "./store.ts";
import { recentChatIds, searchChats } from "../store/chat-list.ts";
import { session, sessionPlace, sessions, summary, thread, threads, timeline, transcriptFile, transcriptState, widgetState } from "./sessions.ts";

/// `?turns=`: how many of a session's latest turns; none (or not a count): all of them, as a device from before reads.
const latest = (v: unknown): number | null => (typeof v === "string" && /^\d{1,6}$/.test(v) ? Number(v) : null);

export const sessionOps: Record<string, ReadOp> = {
  /// Every thread as chat_list has it; it does not use a viewer's unread count (sessions/others.ts).
  threadList: (s) => listThreads(s, "", null, null, "none"),
  /// The first page of chat_list and its count, read together in the reader's snapshot.
  recentChatList: (s, a) => {
    const { ids, total } = recentChatIds(s.db, a.ws, a.home, a.limit);
    const threads = ids.flatMap((id) => {
      const thread = getThread(s, id);
      if (thread === null) return [];
      return [{ thread, sessions: threadSessions(s, id), lastMessage: lastSaid(s, id),
        firstText: thread.title === null && thread.autoTitle === null ? firstText(s, id) : null }];
    });
    const keys = new Set(threads.flatMap((t) => t.sessions.map((m) => m.session)));
    const sessions = [...keys].flatMap((key) => {
      const row = getSession(s, key);
      return row === null ? [] : [{ key: row.key, title: row.title, archivedAt: row.archivedAt, ws: row.ws }];
    });
    return { threads, sessions, total };
  },
  searchChatList: (s, a) => searchChats(s.db, a.ws, a.home, a.limit, a.query, {
    thread: (id) => getThread(s, id), sessions: (id) => threadSessions(s, id), last: (id) => lastSaid(s, id),
    firstText: (id) => firstText(s, id), session: (key) => getSession(s, key),
  }),
  /// A thread's latest `limit` messages, oldest first: the archive review's (sessions/review.ts).
  latestMessages: (s, a) => messagesBefore(s, a.thread, null, a.limit),
  /// One session as lists and events have it (views.rs `summary`).
  summary: (s, a) => summary(s, a.key),
  sessions: (s, a) => sessions(s, a.connect ?? null, a.archived, a.lang, a.viewer ?? null),
  session: (s, a) => session(s, a.key, a.viewer, a.lang, latest(a.turns), a.jobs === "now"),
  timeline: (s, a) => timeline(s, a.key, a.before, a.limit, a.lang, a.from, a.to, a.brief, a.after),
  transcriptState: (s, a) => transcriptState(s, a.key),
  transcriptFile: (s, a) => transcriptFile(s, a.key, a.lang),
  widgetState: (s, a) => widgetState(s, a.key, a.path, a.lang),
  sessionPlace: (s, a) => sessionPlace(s, a.key, a.path ?? "", a.lang),
  threads: (s, a) => threads(s, a.viewer, a.session ?? null, a.lang),
  thread: (s, a) => thread(s, a.viewer, a.id, a.lang),
  /// A thread as each of several viewers has it (`thread`), in one read: what is told to every one after each message.
  /// None for one it is not for.
  threadViews: (s, a) =>
    a.viewers.map((v: { viewer: any; lang: any }) => {
      try {
        return thread(s, v.viewer, String(a.id), v.lang);
      } catch {
        return null;
      }
    }),
  openJobs: (s, a) => openJobs(s, a.viewer, a.lang, a.chats !== false),
  job: (s, a) => job(s, a.id),
  jobLog: (s, a) => jobLog(s, a.id, a.lines),
};
