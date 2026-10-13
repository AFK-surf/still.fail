// What can be done on a chat's page, from anywhere in it, by the chat's key (its draft's: `station:session`, as DraftKey
// gives it): its execution histories and tabs opened, it archived. The page open for that chat (the wide screen's
// pages/ChatPage.tsx, the phone's mobile/Chat.tsx) says how while it is open; what is in it (a message, an agent's
// name, an activity row) only calls these, and is handed no function of the page's.
import { useLayoutEffect, useRef } from "react";

export interface ChatPageActions {
  /** An agent's execution history: at `entry` when given (opened, not toggled), else shown or put away. */
  history(agent: string, entry?: number): void;
  /** What an agent's name beside its messages opens (the phone: its card); its history where not given. */
  agent?(agent: string): void;
  /** A tab of the side panel (a web service's, `service:<job>`; a visualization's), opened in front. */
  tab?(key: string): void;
  /** The 任务 tab, at a job when given. */
  jobs?(job?: string): void;
  /** The chat archived, as its bar's 归档 does (asking first while one of its agents keeps watch). */
  archive(): void;
}

const pages = new Map<string, { current: ChatPageActions }>();

/** For the page open for `chat`: what it does when asked (the functions of its latest render). */
export function useChatPageActions(chat: string, actions: ChatPageActions): void {
  const latest = useRef(actions);
  useLayoutEffect(() => { latest.current = actions; });
  useLayoutEffect(() => {
    pages.set(chat, latest);
    return () => { if (pages.get(chat) === latest) pages.delete(chat); };
  }, [chat]);
}

/** What is done on the page open for a chat, by its key; nothing when none is open. */
export const chatPage = {
  history: (chat: string, agent: string, entry?: number) => pages.get(chat)?.current.history(agent, entry),
  agent: (chat: string, agent: string) => {
    const page = pages.get(chat)?.current;
    if (page?.agent) page.agent(agent); else page?.history(agent);
  },
  tab: (chat: string, key: string) => pages.get(chat)?.current.tab?.(key),
  jobs: (chat: string, job?: string) => pages.get(chat)?.current.jobs?.(job),
  archive: (chat: string) => pages.get(chat)?.current.archive(),
};
