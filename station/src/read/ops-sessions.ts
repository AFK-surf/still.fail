// The reads of sessions, threads and jobs (src/api/routes/sessions.ts asks them), each with the request's `lang`.
import type { ReadOp } from "./ops.ts";
import { job, jobLog, openJobs } from "./jobs.ts";
import { chatHistoryMessages, deliveryCardState, firstText, getSession, getThread, lastSaid, lastSaidText, listThreads, messagesBefore, openedChatSaid, pendingCard, pendingCardNumber, pendingDeliveries, statePendingCard, stateQuestion, threadSessions } from "./store.ts";
import { searchChats } from "../store/chat-list.ts";
import { legacyMergedReadReady } from "../store/legacy-edits-build.ts";
import { recentChatPage } from "./recent-chat.ts";
import { workspaceSessionsToMeasure } from "../jobs/workspace-size.ts";
import { policyChecksRead } from "./policy-checks.ts";
import { archiveLookOf, recentConnectPeople } from "../store/store.ts";
import { session, sessionPlace, sessions, summary, thread, threads, timeline, transcriptFile, transcriptState, widgetState } from "./sessions.ts";

/// `?turns=`: how many of a session's latest turns; none (or not a count): all of them, as a device from before reads.
const latest = (v: unknown): number | null => (typeof v === "string" && /^\d{1,6}$/.test(v) ? Number(v) : null);

export const sessionOps: Record<string, ReadOp> = {
  /// The sessions whose workspaces the station measures this round (jobs/workspace-size.ts).
  sessionsAtWork: (s, a) => workspaceSessionsToMeasure(s.db, a.processes),
  /// What a week's checks say of a workspace's chats, for its archive policy's view (api/overview.ts).
  policyChecks: (s, a) => policyChecksRead(s.db, a.since, a.viewer),
  /// One look of the auto-archive (sessions/lifecycle.ts): every session shown and chat of its own, and what it needs
  /// of those idle long enough. Read on the main thread at each look, it held it.
  archiveLook: (s, a) => archiveLookOf(s.db, Number(a.now), Number(a.after), Number(a.slackAfter)),
  /// The people of a connect's recent threads, learned as it connects (connects/part.ts).
  recentConnectPeople: (s, a) => recentConnectPeople(s.db, a.connect, a.limit),
  /// Every thread as chat_list has it; it does not use a viewer's unread count (sessions/others.ts).
  threadList: (s) => listThreads(s, "", null, null, "none"),
  /// The first page of chat_list and its count, read together in the reader's snapshot.
  recentChatList: (s, a) => {
    const { ids, total } = recentChatPage(s.db, a.ws, a.home, a.limit);
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
  searchChatList: (s, a) => {
    const last = (id: number) => lastSaid(s, id);
    if (a.limit === 0) return searchChats(s.db, a.ws, a.home, a.limit, a.query, last);
    // Keep the readiness decision and all the texts tested by this search in the same snapshot.
    s.db.exec("SAVEPOINT search_chat_list_read");
    try {
      const summary = legacyMergedReadReady(s.db) ? undefined
        : (id: number) => ({ saidText: lastSaidText(s, id), firstText: firstText(s, id) });
      return searchChats(s.db, a.ws, a.home, a.limit, a.query, last, summary);
    } finally { s.db.exec("RELEASE search_chat_list_read"); }
  },
  /// A thread's latest `limit` messages, oldest first: the archive review's (sessions/review.ts).
  latestMessages: (s, a) => messagesBefore(s, a.thread, null, a.limit),
  /// An opener's first message among the latest messages, checked without reading their edits.
  openedChatSaid: (s, a) => openedChatSaid(s, a.thread, a.author, a.agentOnly),
  /// A history page and its optional message boundary, read together.
  chatHistoryMessages: (s, a) => chatHistoryMessages(s, a.thread, a.before ?? null, a.limit),
  /// The card post, if any, that is still pending in a chat history.
  historyPendingCard: (s, a) => pendingCardNumber(s, a.thread),
  /// The visible question a state names, and whether it is still pending.
  stateQuestion: (s, a) => stateQuestion(s, a.key, a.threads, a.ts),
  /// The pending card a state uses when it does not name a message.
  statePendingCard: (s, a) => statePendingCard(s, a.threads),
  /// Card state accompanying a person's delivered message.
  deliveryCardState: (s, a) => deliveryCardState(s, a.thread, a.n),
  /// A session's pending delivery may contain many messages: it shares the bulk reader line.
  pendingDeliveries: (s, a) => pendingDeliveries(s, a.key),
  /// The archive review needs the pending post's merged message as well as its card.
  reviewPendingCard: (s, a) => pendingCard(s, a.thread),
  /// One session as lists and events have it.
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
  openJobs: (s, a) => openJobs(s, a.viewer, a.lang, a.chats !== false),
  job: (s, a) => job(s, a.id),
  jobLog: (s, a) => jobLog(s, a.id, a.lines),
};
