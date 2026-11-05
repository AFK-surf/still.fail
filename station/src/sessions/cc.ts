// A person's message in a still.fail chat copied to Slack and Feishu threads its agents are in (docs/relay.md "抄送"):
// those they tick in the composer's 抄送 menu, where each thread's bot says who wrote it on still.fail (their account
// there, mentioned, where one has their email; else their name and still.fail account) and what. It is the station's words there (no agent's, no person's: the bot never speaks as someone), not delivered to
// the agent, who has the message from the chat already. One that did not go is said in the chat.
import { tr, stationLang } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import type { Attachment } from "../store/rows.ts";
import { CcSessionsUnavailable } from "../store/cc-thread-index.ts";
import type { Hub } from "./hub.ts";

/// What the bot says there: who said it on still.fail, then their words as they wrote them.
export function ccText(who: string, said: string): string {
  const head = tr(stationLang(), "station.cc.said", { who });
  return said === "" ? head : `${head}\n\n${said}`;
}

async function sayFailure(hub: Hub, thread: number, place: string, error: Error): Promise<void> {
  try {
    const chat = hub.store.getThread(thread);
    const here = hub.store.threadSessions(thread)[0];
    if (chat === null || here === undefined) return;
    const note = tr(stationLang(), "station.cc.failed", { place, error: error.message });
    const at = await hub.chat(here.connect).post({ channel: chat.channel, threadTs: chat.threadTs }, note, []);
    hub.store.insertMessage({ thread, ts: at, authorKind: "ember", author: "ember", text: note, attachments: [] });
  } catch (again) {
    log.warn("hub", "a copy's failure was not said in its chat", { thread, error: (again as Error).message });
  }
}

/// Copies `said` (and its files) by `who` (`email`) from chat `thread` to those of its Slack and Feishu threads named in
/// `to` (their thread ids; others are not the chat's, and are left out): done once the promise is (it never fails: what
/// did not go is said in the chat).
export async function cc(hub: Hub, thread: number, who: string, email: string, said: string, files: Attachment[], to: number[]): Promise<void> {
  let picked: ReturnType<Hub["store"]["ccThreads"]>;
  try {
    for (;;) {
      try { picked = hub.store.ccThreads(thread).filter((o) => to.includes(o.thread.id)); break; }
      catch (error) {
        if (!(error instanceof CcSessionsUnavailable) || !hub.prepareCcSessions) throw error;
        await hub.prepareCcSessions(error.sessions);
      }
    }
  } catch (error) {
    const failure = error instanceof Error ? error : new Error(String(error));
    log.warn("hub", "copy destinations could not be prepared", { thread, error: failure.message });
    await sayFailure(hub, thread, "Slack/Feishu", failure);
    return;
  }
  await Promise.all(picked.map(async (o) => {
    try {
      const chat = hub.chat(o.connect);
      const user = (await chat.userOf?.(email).catch(() => null)) ?? null;
      const text = ccText(user !== null ? (chat.mention?.(user) ?? `<@${user}>`) : who === email ? who : `${who} (${email})`, said);
      const ts = await chat.post({ channel: o.thread.channel, threadTs: o.thread.threadTs }, text, files);
      hub.store.insertMessage({ thread: o.thread.id, ts, authorKind: "ember", author: "ember", text, attachments: files });
    } catch (error) {
      log.warn("hub", "a message was not copied to a thread of its chat", { thread, to: o.thread.id, error: (error as Error).message });
      const place = o.thread.surface.startsWith("feishu:") ? "Feishu" : "Slack";
      await sayFailure(hub, thread, place, error instanceof Error ? error : new Error(String(error)));
    }
  }));
}
