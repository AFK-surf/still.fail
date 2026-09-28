import type { ChatItem } from "./api.ts";
import * as css from "./ChatMark.css.ts";

export type ChatTone = "busy" | "done" | "alert";

/** What a chat's row says of it: red when it wants someone now (blocked, failed), yellow while at work, blue when it ended well with something unread; nothing otherwise. */
export function chatTone(item: ChatItem): ChatTone | undefined {
  if (item.state === "block" || item.state === "failed") return "alert";
  if (item.state === "run") return "busy";
  return item.unread ? "done" : undefined;
}

const LABEL: Record<ChatTone, string> = { busy: "工作中", done: "做完了，有新消息", alert: "需要处理" };

/** A chat's state as a mark at its picture's corner (the picture is `position: relative`; it sets `--mark-around`). */
export function ChatMark({ item }: { item: ChatItem }) {
  const tone = chatTone(item);
  return tone ? <span className={css.chatMark} data-tone={tone} role="img" aria-label={LABEL[tone]} /> : null;
}
