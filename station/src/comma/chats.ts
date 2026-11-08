// The Router's writes in the workspace's chats through a Comma connect (`task.say`, surface.ts), apart from the part
// that wires them (module.ts), so that they can be tried alone.
import type { Hub } from "../sessions/hub.ts";
import { say } from "../sessions/lifecycle.ts";
import type { CommaStats } from "./stats.ts";

/// The Router's message in chat `thread` of this station, as `requester` of the Comma connect `connect` (named so in
/// the chat, as a person of that connect is), once per `key`: its `n`. Only a chat of the home workspace on the
/// station's pages; a Slack or Feishu chat is answered where it is.
export function routerSays(hub: Hub, stats: CommaStats, home: string | null, w: { thread: number; text: string; key: string; requester: string; connect: string }): number {
  const had = w.key === "" ? null : stats.said(w.key);
  if (had !== null) return had;
  const members = hub.store.threadSessions(w.thread);
  if (members.length === 0 || members.some((m) => (hub.wsOf(m.session) ?? null) !== home)) throw new Error("no such chat of the workspace");
  const n = say(hub, w.thread, `slack:${w.connect}:${w.requester}`, w.text);
  if (w.key !== "") stats.remember(w.key, n);
  return n;
}
