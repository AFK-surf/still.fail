// A person's message in a still.fail chat copied to Slack and Feishu threads its agents are in (docs/relay.md "抄送"):
// those they tick in the composer's 抄送 menu, where each thread's bot says who wrote it on still.fail and what. It is the station's words there (no agent's, no person's: the bot never speaks as someone), not delivered to
// the agent, who has the message from the chat already. One that did not go is said in the chat.
import { tr, stationLang } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import type { Attachment } from "../store/rows.ts";
import type { Hub } from "./hub.ts";

/// What the bot says there: who said it on still.fail, then their words as they wrote them.
export function ccText(who: string, said: string): string {
  const head = tr(stationLang(), "station.cc.said", { who });
  return said === "" ? head : `${head}\n\n${said}`;
}

/// Copies `said` (and its files) by `who` from chat `thread` to those of its Slack and Feishu threads named in `to`
/// (their thread ids; others are not the chat's, and are left out): done once the promise is (it never fails: what did
/// not go is said in the chat).
export async function cc(hub: Hub, thread: number, who: string, said: string, files: Attachment[], to: number[]): Promise<void> {
  const text = ccText(who, said);
  const picked = hub.store.ccThreads(thread).filter((o) => to.includes(o.thread.id));
  await Promise.all(picked.map(async (o) => {
    try {
      const ts = await hub.chat(o.connect).post({ channel: o.thread.channel, threadTs: o.thread.threadTs }, text, files);
      hub.store.insertMessage({ thread: o.thread.id, ts, authorKind: "ember", author: "ember", text, attachments: files });
    } catch (error) {
      log.warn("hub", "a message was not copied to a thread of its chat", { thread, to: o.thread.id, error: (error as Error).message });
      const chat = hub.store.getThread(thread);
      const here = hub.store.threadSessions(thread)[0];
      if (chat === null || here === undefined) return;
      const place = o.thread.surface.startsWith("feishu:") ? "Feishu" : o.thread.surface.startsWith("x:") ? "X" : "Slack";
      const note = tr(stationLang(), "station.cc.failed", { place, error: (error as Error).message });
      try {
        const at = await hub.chat(here.connect).post({ channel: chat.channel, threadTs: chat.threadTs }, note, []);
        hub.store.insertMessage({ thread, ts: at, authorKind: "ember", author: "ember", text: note, attachments: [] });
      } catch (again) {
        log.warn("hub", "a copy's failure was not said in its chat", { thread, error: (again as Error).message });
      }
    }
  }));
}
