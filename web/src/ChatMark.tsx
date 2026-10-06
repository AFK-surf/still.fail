import { useLayoutEffect, useRef } from "react";
import type { ChatItem } from "./api.ts";
import type { WorkspaceMark } from "./core/shapes.ts";
import { reducedMotion } from "./motion.ts";
import { StatusText, Tip } from "./ui.tsx";
import { jumpTo } from "./jumpTo.ts";
import * as css from "./ChatMark.css.ts";
import { t } from "./i18n.ts";
import { Bell, Check, Hourglass } from "./icons.tsx";

export type ChatTone = "busy" | "done" | "alert" | "wait" | "other";

const TONES: readonly string[] = ["busy", "done", "alert", "wait", "other"];

/**
 * What a chat's row says of it: the core's mark when it gives one (`tone`, with its pieces of work: a blue ring when
 * something waits on the viewer, a grey one when only on others). From a core before it: red when it wants someone now
 * (blocked, failed), yellow while at work, blue when it ended well with something unread; nothing otherwise.
 */
export function chatTone(item: ChatItem): ChatTone | undefined {
  if (item.tone !== undefined) return TONES.includes(item.tone) ? item.tone as ChatTone : undefined;
  if (item.state === "block" || item.state === "failed") return "alert";
  if (item.state === "run") return "busy";
  return item.unread ? "done" : undefined;
}


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
  return tone ? <span ref={mark} className={inline ? css.chatMarkInline : css.chatMark} data-tone={tone} role="img" aria-label={t(`web-main.chatMark.${tone}`)} /> : null;
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
      {(mark.wait ?? 0) > 0 && <span className={css.markCount}><span className={css.chatMarkInline} data-tone="wait" />{mark.wait}</span>}
      {mark.unread > 0 && <span className={css.markCount}><span className={css.chatMarkInline} data-tone="done" />{mark.unread}</span>}
    </span>
  );
}

/**
 * A row's second line from where its chat stands (the core's `stateText`; a core before it: its decision's `decision.text`):
 * 奏 · … (Decision · …) in ink, its lead bold; 要你帮忙：… (Needs you: …) in ink too (it wants the viewer); 出问题：…, 在等：…, 做完了 as quiet as the
 * last message would be. `slot` (the phone's list, as Android's): a lead said as an icon (a bell, an hourglass, a check)
 * stands in the title's mark's column, centred under it, and what follows starts where the title does.
 */
export function WaitingText({ text, className, compactNeed = false, slot = false }: { text: string; className: string; compactNeed?: boolean; slot?: boolean }) {
  const need = compactNeed || slot ? /^(?:要你帮忙|Needs you)(?:[：:]\s*|$)/.exec(text) : null;
  const lead = /^(?:奏|Decision)(?: · |$)/.test(text) ? text.split(" · ")[0]! : "";
  const turn = lead !== "" || /^(?:要你帮忙|Needs you:)/.test(text);
  const icon = slot ? need ?? DONE.exec(text) ?? WAIT.exec(text) : null;
  if (icon) {
    const label = t(need ? "web-main.chatMark.alert" : DONE.test(text) ? "web-main.status.done" : "web-main.status.waiting");
    const rest = text.slice(icon[0].length);
    return (
      <span className={`${className} ${css.leadLine}`} data-turn={turn || undefined} data-state-line="" aria-label={text}>
        <Tip label={label}><span className={css.leadSlot} role="img" aria-label={label}>
          {need ? <Bell size={14} /> : DONE.test(text) ? <Check size={14} strokeWidth={1.7} /> : <Hourglass size={14} strokeWidth={1.7} />}
        </span></Tip>
        {rest && <span className={css.leadRest}>{rest}</span>}
      </span>
    );
  }
  return (
    <span className={className} data-turn={turn || undefined} data-state-line="">
      {need ? <><Tip label={t("web-main.chatMark.alert")}><span className={css.needMark} role="img" aria-label={t("web-main.chatMark.alert")}>
        <Bell size={14} />
      </span></Tip>{text.slice(need[0].length) && <> {text.slice(need[0].length)}</>}</>
        : <>{lead && <b className={css.waitingLead}>{lead}</b>}<StatusText text={text.slice(lead.length)} /></>}
    </span>
  );
}

/** The core's done and waiting leads, in either language (as ui.tsx StatusText reads them). */
const DONE = /^(?:做完了(?:：|$)|Done(?:: |$))/;
const WAIT = /^(?:在等：|等待中$|Waiting(?:: |$))/;

/**
 * A row pressed on its state line (WaitingText) when the core says which message the state is about (`stateAbout`):
 * its chat, as it opens, goes to that message (jumpTo.ts). Pressed elsewhere, about none, or with something unread (the
 * chat opens at the unread line, the message read on from there): nothing here.
 */
export function jumpFromLine(item: ChatItem, target: EventTarget): void {
  if (item.stateAbout == null || item.unread || item.thread == null || !(target instanceof Element) || !target.closest("[data-state-line]")) return;
  jumpTo({ station: item.station, thread: item.thread, seq: item.stateAbout });
}

/** What a row's second line says of where its chat stands, if anything (an older core: only a decision's line). */
export function stateLine(item: ChatItem): string | undefined {
  return item.stateText ?? item.decision?.text;
}
