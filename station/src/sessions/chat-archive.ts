// An agent archives another still.fail chat, here or on a station of its workspace. Use the same lifecycle as the
// app: a chat with its own session takes that session with it; a separate chat is hidden on its own.
import { MANUAL, STILLFAIL_SURFACE } from "../store/rows.ts";
import type { Args } from "./args.ts";
import type { Hub } from "./hub.ts";
import { archiveChat } from "./lifecycle.ts";
import { Refused } from "./neighbours.ts";
import { elsewhere, fromBefore, named, peersOf, scopeOf, sessionThreadOf, threadIn } from "./others.ts";

export const ARCHIVE = "session.archive";

async function archiveHere(hub: Hub, chat: string, ws: string | null, caller: string | null): Promise<string> {
  // A page can show another session's execution history in its query. Archive the page's chat, not that session.
  const reference = chat.includes("/o/") || chat.includes("/chats/") ? chat.split("?")[0]! : chat;
  const what = named(hub, reference, ws);
  const thread = what.type === "thread" ? what.thread : sessionThreadOf(hub, what.key).thread;
  // A chat shared from another workspace can be read or written to, but is not a chat of this workspace.
  if (!threadIn(hub, thread, ws)) throw new Error("that chat is in another workspace: only this workspace's chats can be archived");
  if (thread.surface !== STILLFAIL_SURFACE) throw new Error("only still.fail chats can be archived with chat_archive");
  if (caller !== null && sessionThreadOf(hub, caller).thread.id === thread.id) throw new Error("chat_archive is for another chat, not your own");
  const already = thread.home !== null ? hub.store.getSession(thread.home)?.archivedBy === MANUAL : thread.hiddenBy === MANUAL;
  if (already) return `Already archived: ${chat}.`;
  await archiveChat(hub, thread.id, true);
  return `Archived ${chat}.`;
}

export async function chatArchive(hub: Hub, key: string, args: Args): Promise<string> {
  const chat = typeof args.chat === "string" ? args.chat.trim() : "";
  if (chat === "") throw new Error("chat is required: another chat's link, thread address or session key");
  const station = elsewhere(hub, key, chat);
  if (station === null) return archiveHere(hub, chat, scopeOf(hub, key), key);
  const call = peersOf(hub, key);
  if (!call) throw new Error("other stations cannot be reached from this one yet");
  let answer: any;
  try {
    answer = await call(station, { method: ARCHIVE, session: key, chat });
  } catch (error) {
    const why = (error as Error).message;
    if (error instanceof Refused && fromBefore(why)) throw new Error(`station ${station} is not updated yet: its chats cannot be archived from here`);
    throw new Error(`archive request to station ${station} failed: ${why}. It may already be archived; call chat_archive again with the same chat`);
  }
  if (typeof answer?.text !== "string") throw new Error(`station ${station} answered without an archive result`);
  return answer.text;
}

/// A station of the workspace asks to archive one of its chats here; cross-workspace shares do not grant this action.
export async function archiveForPeer(hub: Hub, request: any, ws: string | null = null): Promise<{ text: string }> {
  const chat = typeof request?.chat === "string" ? request.chat.trim() : "";
  if (chat === "") throw new Error("chat is required");
  return { text: await archiveHere(hub, chat, ws, null) };
}
