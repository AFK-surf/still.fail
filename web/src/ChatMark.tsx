import { useLayoutEffect, useRef } from "react";
import type { ChatItem } from "./api.ts";
import type { WorkspaceMark } from "./core/shapes.ts";
import { reducedMotion } from "./motion.ts";
import * as css from "./ChatMark.css.ts";

export type ChatTone = "busy" | "done" | "alert";

/** What a chat's row says of it: red when it wants someone now (blocked, failed), yellow while at work, blue when it ended well with something unread; nothing otherwise. */
export function chatTone(item: ChatItem): ChatTone | undefined {
  if (item.state === "block" || item.state === "failed") return "alert";
  if (item.state === "run") return "busy";
  return item.unread ? "done" : undefined;
}

const LABEL: Record<ChatTone, string> = { busy: "工作中", done: "做完了，有新消息", alert: "需要处理" };

/**
 * The mark each chat has and since when, to know one that has just come: every list the chat is in pops it (all and
 * mine), also as its row is drawn anew on the way to its new place.
 */
const shown = new Map<string, { tone: ChatTone | undefined; since: number }>();

/**
 * A chat's state as a mark at its picture's corner (the picture is `position: relative`; it sets `--mark-around`), or
 * `inline`, a dot in the line before its title. A mark
 * that comes while the chat is in view (a new message, work begun) pops in; ones there when the list is first drawn do not.
 */
export function ChatMark({ item, inline }: { item: ChatItem; inline?: boolean }) {
  const tone = chatTone(item);
  const mark = useRef<HTMLSpanElement>(null);
  const key = `${item.station}/${item.id}`;
  useLayoutEffect(() => {
    let had = shown.get(key);
    if (!had) shown.set(key, had = { tone, since: -Infinity });
    else if (had.tone !== tone) shown.set(key, had = { tone, since: performance.now() });
    if (!tone || performance.now() - had.since > 300 || !mark.current || reducedMotion()) return;
    mark.current.animate([{ transform: "scale(0)" }, { transform: "scale(1.3)", offset: 0.6 }, { transform: "scale(1)" }], { duration: 320, easing: "ease-out" });
  }, [key, tone]);
  return tone ? <span ref={mark} className={inline ? css.chatMarkInline : css.chatMark} data-tone={tone} role="img" aria-label={LABEL[tone]} /> : null;
}

/**
 * What a workspace has waiting, after its name where workspaces are switched (the core's `workspaceMarks`): a red dot
 * and how many of the chats its person takes part in want them, a blue one and how many are unread; nothing for none.
 */
export function MarkCounts({ mark }: { mark: WorkspaceMark | undefined }) {
  if (!mark?.tone) return null;
  return (
    <span className={css.markCounts} role="img" aria-label={mark.label ?? ""}>
      {mark.alert > 0 && <span className={css.markCount}><span className={css.chatMarkInline} data-tone="alert" />{mark.alert}</span>}
      {mark.unread > 0 && <span className={css.markCount}><span className={css.chatMarkInline} data-tone="done" />{mark.unread}</span>}
    </span>
  );
}
