// slack_api's connect=: a write that would take a session into a Slack conversation as another of the station's bots
// waits for a person. The station posts a card for it in the session's own chat, as the session's message, keeping the
// call in the card (`hold`: only the station makes one, an agent's card has none); choosing to send there makes the
// call, as the session, which then takes part in that thread. Writes in the session's own threads, and reads, go
// through at once.
import { threadAddress } from "../agents/instructions.ts";
import { stationLang, tr } from "../ops/i18n.ts";
import { STILLFAIL_SURFACE } from "../store/store.ts";
import { slackApi } from "./conversations.ts";
import type { Hub } from "./hub.ts";

type Json = any;

/// What a held card keeps: the call, and the label that sends it.
type Hold = { connect: string; method: string; params: Record<string, Json>; send: string };

const holdOf = (card: Json): Hold | null => {
  const h = card?.hold;
  return h !== null && typeof h === "object" && typeof h.connect === "string" && typeof h.method === "string" && typeof h.send === "string" ? h : null;
};

/// Holds `method` (a write in `channel`, in thread `threadTs` when it names one) for a person's approval: a card in the
/// session's still.fail chat. What the agent is told.
export async function holdForApproval(hub: Hub, key: string, connect: string, method: string, params: Record<string, Json>, channel: string, threadTs: string | null): Promise<string> {
  const { store } = hub;
  const chats = store.sessionThreads(key).filter((t) => t.thread.surface === STILLFAIL_SURFACE);
  const home = chats.find((t) => t.thread.home === key) ?? chats[0];
  if (!home) throw new Error("writing in Slack through connect= waits for a person's approval in your still.fail chat, and this session has none");
  const lang = stationLang();
  const chat = hub.chat(connect);
  const bot = hub.config().connects.find((c) => c.id === connect)?.slack.botName || connect;
  const named = chat.knownChannel?.(channel) ?? null;
  const place = channel.startsWith("D") ? tr(lang, "station.chat.directMessage") : `#${named ?? channel}`;
  const where = threadTs !== null ? tr(lang, "station.slackHold.inThread", { where: place }) : place;
  const said = typeof params.text === "string" && params.text.trim() !== "" ? params.text.trim() : null;
  const what = said !== null ? said.split("\n").map((l) => `> ${l}`).join("\n") : `\`\`\`\n${method} ${JSON.stringify(params, null, 2)}\n\`\`\``;
  const text = `${tr(lang, "station.slackHold.ask", { bot, where })}\n\n${what}`;
  const send = tr(lang, "station.slackHold.send");
  const card = {
    type: "options",
    options: [{ label: send, recommended: true }, { label: tr(lang, "station.slackHold.skip") }],
    hold: { connect, method, params, send } satisfies Hold,
  };
  const here = { channel: home.thread.channel, threadTs: home.thread.threadTs };
  const ts = await hub.chat(home.connect).post(here, text, []);
  const [n] = store.insertMessage({ thread: home.thread.id, ts, authorKind: "agent", author: key, text, card });
  hub.shared(home.thread.id, n, key, text);
  const address = threadAddress(home.thread.channel, home.thread.threadTs);
  return `Not sent yet: writing in Slack as another of the station's bots waits for a person. A card in ${address} (message ${ts}) asks them; you are told when they choose (sent: that thread is then one of your conversations; or not sent). Unless other work remains, end your turn need_human: the card is pending.`;
}

/// A person's message in a still.fail chat whose pending card holds a Slack write (before it is recorded): choosing
/// to send makes the call. What the card's session is told then, after the message reaches it; null when no hold was
/// waiting.
export async function answerHold(hub: Hub, thread: number, said: string): Promise<{ session: string; notice: string } | null> {
  const pending = hub.store.pendingCard(thread);
  if (pending === null) return null;
  const [asked, card] = pending;
  const hold = holdOf(card);
  if (hold === null || asked.authorKind !== "agent") return null;
  const session = asked.author;
  if (said.trim() !== hold.send) return { session, notice: `Not sent to Slack: the person answered the approval card (message ${asked.ts}) without choosing "${hold.send}". Nothing was written there.` };
  try {
    const result = await slackApi(hub, session, hold.method, hold.params, hold.connect, false);
    const sent = JSON.parse(result);
    const channel = typeof hold.params.channel === "string" ? hold.params.channel : typeof hold.params.channel_id === "string" ? hold.params.channel_id : null;
    const root = typeof hold.params.thread_ts === "string" ? hold.params.thread_ts : typeof sent?.ts === "string" ? sent.ts : null;
    const there = channel !== null && root !== null ? ` in ${threadAddress(channel, root)}, now one of your conversations (answer there with chat_post)` : "";
    return { session, notice: `Approved and sent: ${hold.method} as ${hold.connect}${there}. Slack answered: ${result}` };
  } catch (error) {
    return { session, notice: `Approved, but sending failed: ${hold.method} as ${hold.connect}: ${(error as Error).message}` };
  }
}
