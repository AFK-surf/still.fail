// The Router's reads and writes in the workspace's chats through a Comma connect (surface.ts), apart from the part
// that wires them (module.ts), so that they can be tried alone.
import type { Hub } from "../sessions/hub.ts";
import { say } from "../sessions/lifecycle.ts";
import type { WorkspaceReads } from "./peer.ts";
import { chatOf, type CommaStats } from "./stats.ts";

type Json = any;

/// A chat's messages and title for the Router, only after the station holding the chat confirms its workspace.
export async function routerReads(stats: CommaStats, reads: Pick<WorkspaceReads, "home" | "here" | "there">, ref: string, after: number, limit: number): Promise<Json> {
  const chat = chatOf(ref);
  if (chat === null) throw new Error("no such chat");
  const args = { thread: chat.thread, after, limit };
  const home = reads.home();
  const got = JSON.parse(chat.station === null
    ? await reads.here("outflowMessages", home === null ? args : { ...args, ws: { workspace: home, home: true } })
    : await reads.there(chat.station, "outflowMessages", args));
  if (got === null) throw new Error("no such chat of the workspace");
  return {
    title: stats.taskTitle(ref),
    messages: (got.messages as Json[]).filter((m) => m.kind === "message").map((m) => ({
      seq: m.n, author_kind: m.authorKind, author: m.person?.name ?? m.person?.email ?? m.author, text: m.text, at: m.at,
    })),
    through: got.last,
  };
}

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
